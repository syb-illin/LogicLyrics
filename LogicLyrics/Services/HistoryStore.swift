import Foundation

private struct HistoryEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let entries: [SongHistoryEntry]
}

private enum HistoryRepositoryError: LocalizedError, Sendable {
    case corrupt(backupName: String)
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .corrupt(let backupName):
            L10n.format("The history file was unreadable. A backup was preserved as %@.", backupName)
        case .unsupportedVersion(let version):
            L10n.format("This history was created by a newer app version (schema %d). Update Logic Lyrics before opening it.", version)
        }
    }
}

actor HistoryRepository {
    private static let currentSchemaVersion = 3
    private let fileURL: URL

    init(fileManager: FileManager = .default) throws {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = base.appendingPathComponent("LogicLyrics", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("history.json")
    }

    func load() throws -> [SongHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        do {
            if let envelope = try? JSONDecoder().decode(HistoryEnvelope.self, from: data) {
                guard envelope.schemaVersion <= Self.currentSchemaVersion else {
                    throw HistoryRepositoryError.unsupportedVersion(envelope.schemaVersion)
                }
                return envelope.entries
            }
            return try JSONDecoder().decode([SongHistoryEntry].self, from: data)
        } catch let error as HistoryRepositoryError {
            throw error
        } catch {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("history-corrupt-\(formatter.string(from: Date())).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            throw HistoryRepositoryError.corrupt(backupName: backup.lastPathComponent)
        }
    }

    func save(_ entries: [SongHistoryEntry]) throws {
        let data = try JSONEncoder().encode(HistoryEnvelope(
            schemaVersion: Self.currentSchemaVersion,
            entries: entries
        ))
        try data.write(to: fileURL, options: .atomic)
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [SongHistoryEntry] = []
    @Published var searchText = ""
    @Published private(set) var persistenceError: UserAlert?

    private let repository: HistoryRepository?
    private var saveTask: Task<Void, Never>?
    private var hasFinishedInitialLoad = false
    private var saveRequestedDuringInitialLoad = false
    private var dirtyLyrics = Set<UUID>()
    private var dirtyPrompts = Set<UUID>()

    var filteredEntries: [SongHistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.projectName.localizedCaseInsensitiveContains(query)
            || $0.searchableLyrics.localizedCaseInsensitiveContains(query)
            || $0.referenceArtist.localizedCaseInsensitiveContains(query)
        }
    }

    init() {
        do { repository = try HistoryRepository() }
        catch {
            repository = nil
            let errorType = String(describing: type(of: error))
            AppLog.history.error("History repository initialization failed error_type=\(errorType, privacy: .public)")
            persistenceError = .error(error, context: L10n.text("History unavailable"))
        }
        load()
    }

    @discardableResult
    func recordProject(
        name: String, path: String, noteKey: String, alternative: String,
        lyrics: String, bpm: Double?, musicalKey: String?
    ) -> UUID {
        let normalizedPath = Self.normalizedProjectPath(path)
        if let index = entries.firstIndex(where: { $0.projectPath == normalizedPath }) {
            entries[index].projectName = name
            entries[index].noteKey = noteKey
            entries[index].alternative = alternative
            entries[index].reconcileSourceLyrics(lyrics)
            entries[index].bpm = bpm
            entries[index].musicalKey = musicalKey
            entries[index].updatedAt = Date()
            sortAndScheduleSave()
            return entries[index].id
        }

        let entry = SongHistoryEntry(
            id: UUID(), projectName: name, projectPath: normalizedPath,
            noteKey: noteKey, alternative: alternative, lyrics: lyrics,
            prompt: "", referenceArtist: "", allowsFemaleBackingVocals: false,
            bpm: bpm, musicalKey: musicalKey, createdAt: Date(), updatedAt: Date()
        )
        entries.insert(entry, at: 0)
        scheduleSave()
        return entry.id
    }

    func updateLyrics(entryID: UUID, lyrics: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].applyLocalEdit(lyrics)
        entries[index].updatedAt = Date()
        dirtyLyrics.insert(entryID)
        sortAndScheduleSave()
    }

    func savePrompt(entryID: UUID, prompt: String, referenceArtist: String, allowsFemaleBackingVocals: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].prompt = prompt
        entries[index].referenceArtist = referenceArtist
        entries[index].allowsFemaleBackingVocals = allowsFemaleBackingVocals
        entries[index].updatedAt = Date()
        dirtyPrompts.insert(entryID)
        sortAndScheduleSave()
    }

    func entry(id: UUID?) -> SongHistoryEntry? {
        guard let id else { return nil }
        return entries.first { $0.id == id }
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        scheduleSave()
    }

    func flush() {
        scheduleSave(delayNanoseconds: 0)
    }

    func dismissPersistenceError() { persistenceError = nil }

    private func load() {
        guard let repository else { return }
        Task { [weak self] in
            let startedAt = Date()
            AppLog.history.info("History load started")
            do {
                let decoded = try await repository.load()
                let loaded = Self.consolidated(decoded)
                let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                AppLog.history.info("History load succeeded duration_ms=\(durationMilliseconds, privacy: .public) entries=\(loaded.count, privacy: .public)")
                guard let self else { return }
                if self.entries.isEmpty {
                    self.entries = loaded
                } else {
                    let currentIDs = Set(self.entries.map(\.id))
                    self.entries = Self.consolidated(
                        self.entries + loaded,
                        preferredIDs: currentIDs,
                        protectedLyricsIDs: self.dirtyLyrics,
                        protectedPromptIDs: self.dirtyPrompts
                    )
                }
                self.hasFinishedInitialLoad = true
                // Persist schema migration and duplicate consolidation even when
                // the user does not edit anything during this launch.
                self.scheduleSave(delayNanoseconds: 0)
            } catch {
                let errorType = String(describing: type(of: error))
                AppLog.history.error("History load failed error_type=\(errorType, privacy: .public)")
                guard let self else { return }
                self.hasFinishedInitialLoad = true
                self.persistenceError = .error(error, context: L10n.text("Unable to read history"))
                if self.saveRequestedDuringInitialLoad, !self.entries.isEmpty {
                    self.scheduleSave(delayNanoseconds: 0)
                }
            }
        }
    }

    private func sortAndScheduleSave() {
        entries.sort { $0.updatedAt > $1.updatedAt }
        scheduleSave()
    }

    private func scheduleSave(delayNanoseconds: UInt64 = 250_000_000) {
        guard let repository else { return }
        guard hasFinishedInitialLoad else {
            saveRequestedDuringInitialLoad = true
            return
        }
        saveRequestedDuringInitialLoad = false
        let snapshot = entries
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                if delayNanoseconds > 0 {
                    try await Task<Never, Never>.sleep(nanoseconds: delayNanoseconds)
                }
                try Task.checkCancellation()
                try await repository.save(snapshot)
                AppLog.history.debug("History save succeeded entries=\(snapshot.count, privacy: .public)")
            } catch is CancellationError {
                return
            } catch {
                let errorType = String(describing: type(of: error))
                AppLog.history.error("History save failed error_type=\(errorType, privacy: .public)")
                self?.persistenceError = .error(error, context: L10n.text("Unable to save history"))
            }
        }
    }

    /// Produces one stable history row per project path. In-memory IDs can be
    /// preferred during an asynchronous load so UI selections remain valid.
    static func consolidated(
        _ values: [SongHistoryEntry],
        preferredIDs: Set<UUID> = [],
        protectedLyricsIDs: Set<UUID> = [],
        protectedPromptIDs: Set<UUID> = []
    ) -> [SongHistoryEntry] {
        let groups = Dictionary(grouping: values) { entry -> String in
            let path = normalizedProjectPath(entry.projectPath)
            return path.isEmpty ? "missing-path:\(entry.id.uuidString)" : path
        }
        return groups.values
            .compactMap {
                merge(
                    Array($0), preferredIDs: preferredIDs,
                    protectedLyricsIDs: protectedLyricsIDs,
                    protectedPromptIDs: protectedPromptIDs
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func merge(
        _ group: [SongHistoryEntry],
        preferredIDs: Set<UUID>,
        protectedLyricsIDs: Set<UUID>,
        protectedPromptIDs: Set<UUID>
    ) -> SongHistoryEntry? {
        let sorted = group.sorted { $0.updatedAt > $1.updatedAt }
        guard var merged = sorted.first(where: { preferredIDs.contains($0.id) }) ?? sorted.first else {
            return nil
        }

        let verified = sorted.filter { !$0.needsSourceReconciliation }
        let sourcePool = verified.isEmpty ? sorted : verified
        let preferredSourcePool = sourcePool.filter { preferredIDs.contains($0.id) }
        let effectiveSourcePool = preferredSourcePool.isEmpty ? sourcePool : preferredSourcePool
        guard let sourceOwner = effectiveSourcePool.max(by: {
            sourceQuality($0.sourceLyrics) < sourceQuality($1.sourceLyrics)
        }) else {
            return merged
        }
        merged.projectPath = normalizedProjectPath(sourceOwner.projectPath)
        merged.projectName = sorted.first(where: { !$0.projectName.isEmpty })?.projectName ?? merged.projectName
        merged.noteKey = sourceOwner.noteKey
        merged.alternative = sourceOwner.alternative
        merged.reconcileSourceLyrics(sourceOwner.sourceLyrics)
        merged.markSourceForReconciliation(verified.isEmpty)

        let protectedLyrics = sorted.first(where: { protectedLyricsIDs.contains($0.id) })
        let editedOwner = protectedLyrics ?? sorted.first(where: { $0.editedLyrics != nil })
        merged.replaceEditedLyrics(editedOwner?.editedLyrics)

        var recovered: [String] = []
        for entry in sorted {
            recovered.append(contentsOf: entry.recoveredLyrics)
            if entry.id != sourceOwner.id { recovered.append(entry.sourceLyrics) }
            if let edited = entry.editedLyrics, edited != editedOwner?.editedLyrics {
                recovered.append(edited)
            }
        }
        merged.replaceRecoveredLyrics(recovered)

        let protectedPrompt = sorted.first(where: { protectedPromptIDs.contains($0.id) })
        let promptOwner = protectedPrompt ?? sorted.first(where: { !$0.prompt.isEmpty })
        if let promptOwner {
            merged.prompt = promptOwner.prompt
            merged.referenceArtist = promptOwner.referenceArtist
            merged.allowsFemaleBackingVocals = promptOwner.allowsFemaleBackingVocals
        }
        merged.bpm = sourceOwner.bpm ?? sorted.compactMap(\.bpm).first
        merged.musicalKey = sourceOwner.musicalKey ?? sorted.compactMap(\.musicalKey).first
        merged.updatedAt = sorted.map(\.updatedAt).max() ?? merged.updatedAt
        return merged
    }

    private static func normalizedProjectPath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func sourceQuality(_ text: String) -> (Int, Int, Int) {
        let lines = text.split(whereSeparator: \.isNewline).count
        let markers = text.components(separatedBy: "[").dropFirst().filter { component in
            let label = component.prefix { $0 != "]" }.lowercased()
            return ["verse", "chorus", "bridge", "intro", "outro", "hook", "refrain"]
                .contains(where: { label.hasPrefix($0) })
        }.count
        return (markers, lines, text.count)
    }
}
