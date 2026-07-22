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
    private static let currentSchemaVersion = 4
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
    @Published private(set) var operationState = OperationState.idle

    private let repository: HistoryRepository?
    private let locator: any ProjectLocating
    private let archiveService: HistoryArchiveService
    private var saveTask: Task<Void, Never>?
    private var transferTask: Task<Void, Never>?
    private var transferOperationID = UUID()
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

    init(
        locator: any ProjectLocating = ProjectLocator(),
        archiveService: HistoryArchiveService = HistoryArchiveService()
    ) {
        self.locator = locator
        self.archiveService = archiveService
        do { repository = try HistoryRepository() }
        catch {
            repository = nil
            let errorType = String(describing: type(of: error))
            AppLog.history.error("History repository initialization failed error_type=\(errorType, privacy: .public)")
            persistenceError = .error(error, context: L10n.text("History unavailable"))
        }
        load()
    }

    private init(
        inMemoryEntries: [SongHistoryEntry],
        locator: any ProjectLocating = ProjectLocator(),
        archiveService: HistoryArchiveService = HistoryArchiveService()
    ) {
        repository = nil
        self.locator = locator
        self.archiveService = archiveService
        entries = inMemoryEntries
        hasFinishedInitialLoad = true
    }

    static func configuredForCurrentProcess() -> HistoryStore {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else {
            return HistoryStore()
        }

        let createdAt = Date(timeIntervalSinceReferenceDate: 700_000_000)
        var plaid = SongHistoryEntry(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
            projectName: "Plaid", projectPath: "/tmp/Plaid.logicx",
            noteKey: "005#2", alternative: "005",
            lyrics: "Demo Song\n[Verse 1]\nLive project lyrics\n[Chorus]\nStay with me",
            prompt: "Suno prompt with BPM 130 and F major",
            referenceArtist: "Reference Band", allowsFemaleBackingVocals: true,
            bpm: 130, musicalKey: "F major", createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(200)
        )
        plaid.applyLocalEdit("Demo Song\n[Verse 1]\nEdited local lyrics\n[Chorus]\nStay with me")
        plaid.recover("Demo Song\n[Verse 1]\nRecovered legacy lyrics")
        let second = SongHistoryEntry(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            projectName: "Human Geology", projectPath: "/tmp/Human Geology.logicx",
            noteKey: "000#1", alternative: "000",
            lyrics: "[Verse 1]\nSecond project lyrics", prompt: "",
            referenceArtist: "", allowsFemaleBackingVocals: false,
            bpm: 112, musicalKey: "A minor", createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(100)
        )
        return HistoryStore(inMemoryEntries: [plaid, second])
    }

    @discardableResult
    func recordProject(
        name: String, url: URL, noteKey: String, alternative: String,
        lyrics: String, bpm: Double?, musicalKey: String?
    ) -> UUID {
        let location = locator.capture(url)
        let normalizedPath = Self.normalizedProjectPath(location.url.path)
        if let index = index(matching: location) {
            entries[index].projectName = name
            entries[index].updateProjectLocation(
                path: normalizedPath,
                fileID: location.fileID,
                bookmark: location.bookmark ?? entries[index].projectBookmark
            )
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
            bpm: bpm, musicalKey: musicalKey, createdAt: Date(), updatedAt: Date(),
            projectFileID: location.fileID, projectBookmark: location.bookmark
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

    func restoreRevision(entryID: UUID, lyrics: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].restoreRevision(lyrics)
        entries[index].updatedAt = Date()
        dirtyLyrics.insert(entryID)
        sortAndScheduleSave()
    }

    func revertToProjectLyrics(entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              entries[index].hasLocalEdits else { return }
        entries[index].revertToSource()
        entries[index].updatedAt = Date()
        dirtyLyrics.insert(entryID)
        sortAndScheduleSave()
    }

    func resolveProjectURL(entryID: UUID) throws -> URL {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            throw ProjectLocatorError.unavailable
        }
        let location = try locator.resolve(
            path: entries[index].projectPath,
            bookmark: entries[index].projectBookmark
        )
        refreshLocation(at: index, from: location)
        return location.url
    }

    func relocateProject(entryID: UUID, to url: URL) throws -> URL {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            throw ProjectLocatorError.unavailable
        }
        let location = try locator.resolve(path: url.path, bookmark: nil)
        refreshLocation(at: index, from: location)
        return location.url
    }

    func exportHistory(to destination: URL) {
        beginTransfer(message: L10n.text("Exporting song history…")) { [archiveService, entries] in
            try archiveService.write(entries, to: destination)
            return .exported(entries.count)
        }
    }

    func importHistory(from source: URL) {
        beginTransfer(message: L10n.text("Importing song history…")) { [archiveService] in
            .imported(try archiveService.read(from: source))
        }
    }

    func cancelTransfer() {
        guard operationState.isRunning else { return }
        transferTask?.cancel()
    }

    func entry(id: UUID?) -> SongHistoryEntry? {
        guard let id else { return nil }
        return entries.first { $0.id == id }
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        dirtyLyrics.remove(id)
        dirtyPrompts.remove(id)
        scheduleSave()
    }

    func flush() {
        scheduleSave(delayNanoseconds: 0)
    }

    func dismissPersistenceError() { persistenceError = nil }

    private enum TransferResult: Sendable {
        case exported(Int)
        case imported([SongHistoryEntry])
    }

    private func beginTransfer(
        message: String,
        operation: @escaping @Sendable () throws -> TransferResult
    ) {
        transferTask?.cancel()
        let operationID = UUID()
        transferOperationID = operationID
        operationState = .running(message: message, startedAt: Date())
        transferTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try Task<Never, Never>.checkCancellation()
                let result = try operation()
                try Task<Never, Never>.checkCancellation()
                await self?.completeTransfer(result, operationID: operationID)
            } catch is CancellationError {
                await self?.finishTransfer(operationID: operationID)
            } catch {
                await self?.failTransfer(error, operationID: operationID)
            }
        }
    }

    private func completeTransfer(_ result: TransferResult, operationID: UUID) {
        guard transferOperationID == operationID else { return }
        switch result {
        case .exported(let count):
            persistenceError = UserAlert(
                kind: .success,
                title: L10n.text("History Exported"),
                message: L10n.format("%d songs were exported successfully.", count)
            )
        case .imported(let imported):
            let currentIDs = Set(entries.map(\.id))
            entries = Self.consolidated(
                entries + imported,
                preferredIDs: currentIDs,
                protectedLyricsIDs: currentIDs,
                protectedPromptIDs: currentIDs
            )
            scheduleSave(delayNanoseconds: 0)
            persistenceError = UserAlert(
                kind: .success,
                title: L10n.text("History Imported"),
                message: L10n.format("%d songs were imported and merged safely.", imported.count)
            )
        }
        finishTransfer(operationID: operationID)
    }

    private func failTransfer(_ error: Error, operationID: UUID) {
        guard transferOperationID == operationID else { return }
        persistenceError = .error(error, context: L10n.text("History Transfer Failed"))
        finishTransfer(operationID: operationID)
    }

    private func finishTransfer(operationID: UUID) {
        guard transferOperationID == operationID else { return }
        operationState = .idle
        transferTask = nil
    }

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

    /// Produces one stable history row per filesystem identity, falling back
    /// to a normalized path for legacy records without an identity.
    static func consolidated(
        _ values: [SongHistoryEntry],
        preferredIDs: Set<UUID> = [],
        protectedLyricsIDs: Set<UUID> = [],
        protectedPromptIDs: Set<UUID> = []
    ) -> [SongHistoryEntry] {
        var identifiedPathOwners = [String: SongHistoryEntry]()
        for entry in values where entry.projectFileID != nil {
            let path = normalizedProjectPath(entry.projectPath)
            if let current = identifiedPathOwners[path], current.updatedAt >= entry.updatedAt { continue }
            identifiedPathOwners[path] = entry
        }
        let groups = Dictionary(grouping: values) { entry -> String in
            if let fileID = entry.projectFileID { return "file:\(fileID)" }
            let path = normalizedProjectPath(entry.projectPath)
            if let migratedFileID = identifiedPathOwners[path]?.projectFileID {
                return "file:\(migratedFileID)"
            }
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
        let locationOwner = sorted.first(where: {
            preferredIDs.contains($0.id) && ($0.projectFileID != nil || $0.projectBookmark != nil)
        }) ?? sorted.first(where: { $0.projectBookmark != nil })
            ?? sorted.first(where: { $0.projectFileID != nil })
            ?? sourceOwner
        merged.updateProjectLocation(
            path: normalizedProjectPath(locationOwner.projectPath),
            fileID: locationOwner.projectFileID,
            bookmark: locationOwner.projectBookmark
        )
        merged.projectName = locationOwner.projectName.isEmpty
            ? (sorted.first(where: { !$0.projectName.isEmpty })?.projectName ?? merged.projectName)
            : locationOwner.projectName
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

    private func index(matching location: ProjectLocation) -> Int? {
        let normalizedPath = Self.normalizedProjectPath(location.url.path)
        if let fileID = location.fileID,
           let exact = entries.firstIndex(where: { $0.projectFileID == fileID }) {
            return exact
        }
        return entries.firstIndex {
            $0.projectFileID == nil && Self.normalizedProjectPath($0.projectPath) == normalizedPath
        }
    }

    private func refreshLocation(at index: Int, from location: ProjectLocation) {
        let normalizedPath = Self.normalizedProjectPath(location.url.path)
        entries[index].projectName = location.url.deletingPathExtension().lastPathComponent
        entries[index].updateProjectLocation(
            path: normalizedPath,
            fileID: location.fileID,
            bookmark: location.bookmark ?? entries[index].projectBookmark
        )
        entries[index].updatedAt = Date()
        sortAndScheduleSave()
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
