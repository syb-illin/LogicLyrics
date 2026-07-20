import Foundation

private struct HistoryEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let entries: [SongHistoryEntry]
}

private enum HistoryRepositoryError: LocalizedError, Sendable {
    case corrupt(backupName: String)

    var errorDescription: String? {
        switch self {
        case .corrupt(let backupName):
            L10n.format("The history file was unreadable. A backup was preserved as %@.", backupName)
        }
    }
}

actor HistoryRepository {
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
                return envelope.entries
            }
            return try JSONDecoder().decode([SongHistoryEntry].self, from: data)
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
        let data = try JSONEncoder().encode(HistoryEnvelope(schemaVersion: 2, entries: entries))
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
    private var dirtyLyrics = Set<UUID>()
    private var dirtyPrompts = Set<UUID>()

    var filteredEntries: [SongHistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.projectName.localizedCaseInsensitiveContains(query)
            || $0.lyrics.localizedCaseInsensitiveContains(query)
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
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if let index = entries.firstIndex(where: {
            $0.projectPath == normalizedPath && ($0.noteKey == noteKey || $0.noteKey == "legacy")
        }) {
            entries[index].projectName = name
            entries[index].noteKey = noteKey
            entries[index].alternative = alternative
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
        entries[index].lyrics = lyrics
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
                let loaded = try await repository.load().sorted { $0.updatedAt > $1.updatedAt }
                let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                AppLog.history.info("History load succeeded duration_ms=\(durationMilliseconds, privacy: .public) entries=\(loaded.count, privacy: .public)")
                guard let self else { return }
                if self.entries.isEmpty {
                    self.entries = loaded
                } else {
                    for loadedEntry in loaded {
                        if let index = self.entries.firstIndex(where: {
                            $0.projectPath == loadedEntry.projectPath
                            && ($0.noteKey == loadedEntry.noteKey || loadedEntry.noteKey == "legacy")
                        }) {
                            if !self.dirtyLyrics.contains(self.entries[index].id) {
                                self.entries[index].lyrics = loadedEntry.lyrics
                            }
                            if !self.dirtyPrompts.contains(self.entries[index].id) {
                                self.entries[index].prompt = loadedEntry.prompt
                                self.entries[index].referenceArtist = loadedEntry.referenceArtist
                                self.entries[index].allowsFemaleBackingVocals = loadedEntry.allowsFemaleBackingVocals
                            }
                        } else {
                            self.entries.append(loadedEntry)
                        }
                    }
                    self.entries.sort { $0.updatedAt > $1.updatedAt }
                    self.scheduleSave(delayNanoseconds: 0)
                }
            } catch {
                let errorType = String(describing: type(of: error))
                AppLog.history.error("History load failed error_type=\(errorType, privacy: .public)")
                self?.persistenceError = .error(error, context: L10n.text("Unable to read history"))
            }
        }
    }

    private func sortAndScheduleSave() {
        entries.sort { $0.updatedAt > $1.updatedAt }
        scheduleSave()
    }

    private func scheduleSave(delayNanoseconds: UInt64 = 250_000_000) {
        guard let repository else { return }
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
}
