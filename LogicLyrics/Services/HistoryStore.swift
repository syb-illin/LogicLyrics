import Foundation

private struct HistoryEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let entries: [SongHistoryEntry]
}

enum HistoryRepositoryError: LocalizedError, Sendable {
    case corrupt(backupName: String)
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .corrupt(let backupName):
            L10n.format("The history file was unreadable. A backup was preserved as %@.", backupName)
        case .unsupportedVersion(let version):
            L10n.format(
                "This history was created by a newer app version (schema %d). Update Logic Lyrics before opening it.",
                version
            )
        }
    }
}

protocol HistoryPersisting: Sendable {
    func load() async throws -> [SongHistoryEntry]
    func save(_ entries: [SongHistoryEntry]) async throws
}

actor HistoryRepository: HistoryPersisting {
    static let currentSchemaVersion = 5
    private let fileManager: FileManager
    private let fileURL: URL
    private let legacyBundleImportURL: URL

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) throws {
        let base: URL
        if let applicationSupportURL {
            base = applicationSupportURL
        } else if let discovered = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            base = discovered
        } else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = base.appendingPathComponent("LogicLyrics", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileManager = fileManager
        fileURL = directory.appendingPathComponent("history.json")
        legacyBundleImportURL = directory.appendingPathComponent("history-legacy-bundle-import.json")
    }

    func load() async throws -> [SongHistoryEntry] {
        let hasPrimary = fileManager.fileExists(atPath: fileURL.path)
        let hasLegacyImport = fileManager.fileExists(atPath: legacyBundleImportURL.path)
        guard hasPrimary || hasLegacyImport else { return [] }
        do {
            var entries: [SongHistoryEntry] = []
            if hasPrimary {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let decoded = try decode(data)
                if decoded.schemaVersion < Self.currentSchemaVersion {
                    preserveSchemaBackup(data, schemaVersion: decoded.schemaVersion)
                }
                entries.append(contentsOf: decoded.entries)
            }
            if hasLegacyImport {
                let data = try Data(contentsOf: legacyBundleImportURL, options: [.mappedIfSafe])
                entries.append(contentsOf: try decode(data).entries)
            }
            return entries
        } catch let error as HistoryRepositoryError {
            throw error
        } catch {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("history-corrupt-\(formatter.string(from: Date())).json")
            let corruptSource = hasPrimary ? fileURL : legacyBundleImportURL
            try? fileManager.copyItem(at: corruptSource, to: backup)
            throw HistoryRepositoryError.corrupt(backupName: backup.lastPathComponent)
        }
    }

    func save(_ entries: [SongHistoryEntry]) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(HistoryEnvelope(
            schemaVersion: Self.currentSchemaVersion,
            entries: entries
        ))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        if fileManager.fileExists(atPath: legacyBundleImportURL.path) {
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("history-legacy-bundle-backup.json")
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: legacyBundleImportURL, to: backup)
            }
            try fileManager.removeItem(at: legacyBundleImportURL)
        }
    }

    private func decode(_ data: Data) throws -> (schemaVersion: Int, entries: [SongHistoryEntry]) {
        if let envelope = try? JSONDecoder().decode(HistoryEnvelope.self, from: data) {
            guard envelope.schemaVersion <= Self.currentSchemaVersion else {
                throw HistoryRepositoryError.unsupportedVersion(envelope.schemaVersion)
            }
            return (envelope.schemaVersion, envelope.entries)
        }
        return (1, try JSONDecoder().decode([SongHistoryEntry].self, from: data))
    }

    private func preserveSchemaBackup(_ data: Data, schemaVersion: Int) {
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("history-schema-\(schemaVersion)-backup.json")
        guard !fileManager.fileExists(atPath: backup.path) else { return }
        try? data.write(to: backup, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [SongHistoryEntry] = []
    @Published var searchText = ""
    @Published var showsOnlyProjectsWithoutLyrics = false
    @Published private(set) var persistenceError: UserAlert?

    private let repository: (any HistoryPersisting)?
    private let locator: any ProjectLocating
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var hasFinishedInitialLoad = false
    private var saveRequestedDuringInitialLoad = false

    var filteredEntries: [SongHistoryEntry] {
        HistorySearch.filter(
            entries,
            query: searchText,
            onlyWithoutLyrics: showsOnlyProjectsWithoutLyrics
        )
    }

    init(locator: any ProjectLocating = ProjectLocator()) {
        self.locator = locator
        do { repository = try HistoryRepository() }
        catch {
            repository = nil
            let errorType = String(describing: type(of: error))
            AppLog.history.error(
                "History repository initialization failed error_type=\(errorType, privacy: .public)"
            )
            persistenceError = .error(error, context: L10n.text("History unavailable"))
        }
        load()
    }

    init(
        inMemoryEntries: [SongHistoryEntry],
        locator: any ProjectLocating = ProjectLocator(),
        repository: (any HistoryPersisting)? = nil
    ) {
        self.repository = repository
        self.locator = locator
        entries = Self.consolidated(inMemoryEntries)
        hasFinishedInitialLoad = true
    }

    deinit {
        loadTask?.cancel()
        saveTask?.cancel()
    }

    static func configuredForCurrentProcess() -> HistoryStore {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else {
            return HistoryStore()
        }
        let createdAt = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let make: (String, String, String, Double, String, TimeInterval, Bool) -> SongHistoryEntry = {
            id, name, lyrics, bpm, key, offset, pinned in
            SongHistoryEntry(
                id: UUID(uuidString: id) ?? UUID(),
                projectName: name,
                projectPath: "/tmp/\(name).logicx",
                alternative: "000",
                sourceLyrics: lyrics,
                bpm: bpm,
                musicalKey: key,
                diagnostics: ExtractionDiagnostics(
                    outcome: lyrics.isEmpty ? .noEmbeddedRichText : .selected,
                    embeddedRichTextCount: lyrics.isEmpty ? 0 : 1,
                    decodedCandidateCount: lyrics.isEmpty ? 0 : 1,
                    likelyProjectNotesCount: lyrics.isEmpty ? 0 : 1,
                    selectedCandidateIndex: lyrics.isEmpty ? nil : 0
                ),
                sourceStateToken: "ui-test-\(name)",
                isPinned: pinned,
                createdAt: createdAt,
                updatedAt: createdAt.addingTimeInterval(offset)
            )
        }
        return HistoryStore(inMemoryEntries: [
            make(
                "11111111-1111-1111-1111-111111111111", "Plaid",
                "Demo Song\n[Verse 1]\nLive project lyrics\n[Chorus]\nStay with me",
                130, "F major", 200, true
            ),
            make(
                "22222222-2222-2222-2222-222222222222", "Human Geology",
                "[Verse 1]\nSecond project lyrics", 112, "A minor", 100, false
            ),
            make(
                "33333333-3333-3333-3333-333333333333", "at last",
                "[Verse 1]\nA completely unrelated lyric", 110, "C major", 50, false
            ),
            make(
                "44444444-4444-4444-4444-444444444444", "instrumental draft",
                "", 118, "D minor", 25, false
            )
        ])
    }

    @discardableResult
    func recordProject(name: String, url: URL, result: LogicProjectReader.Result) -> UUID {
        let location = locator.capture(url)
        let normalizedPath = Self.normalizedProjectPath(location.url.path)
        let note = result.notes.first
        if let index = index(matching: location) {
            entries[index].projectName = name
            entries[index].updateProjectLocation(
                path: normalizedPath,
                fileID: location.fileID,
                bookmark: location.bookmark ?? entries[index].projectBookmark
            )
            entries[index].updateSource(
                lyrics: note?.text ?? "",
                alternative: result.selectedAlternative,
                bpm: result.bpm,
                musicalKey: result.musicalKey,
                diagnostics: result.diagnostics,
                sourceStateToken: result.sourceStateToken
            )
            entries[index].updatedAt = Date()
            sortAndScheduleSave()
            return entries[index].id
        }

        let entry = SongHistoryEntry(
            id: UUID(),
            projectName: name,
            projectPath: normalizedPath,
            alternative: result.selectedAlternative,
            sourceLyrics: note?.text ?? "",
            bpm: result.bpm,
            musicalKey: result.musicalKey,
            diagnostics: result.diagnostics,
            sourceStateToken: result.sourceStateToken,
            createdAt: Date(),
            updatedAt: Date(),
            projectFileID: location.fileID,
            projectBookmark: location.bookmark
        )
        entries.append(entry)
        sortAndScheduleSave()
        return entry.id
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

    func entry(id: UUID?) -> SongHistoryEntry? {
        guard let id else { return nil }
        return entries.first { $0.id == id }
    }

    func togglePin(entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].isPinned.toggle()
        sortAndScheduleSave()
    }

    func remove(entryID: UUID) {
        entries.removeAll { $0.id == entryID }
        scheduleSave()
    }

    func clear() {
        entries.removeAll()
        scheduleSave()
    }

    @discardableResult
    func removeUnavailableProjects() -> Int {
        let unavailableIDs = entries.compactMap { entry -> UUID? in
            (try? locator.resolve(path: entry.projectPath, bookmark: entry.projectBookmark)) == nil
                ? entry.id : nil
        }
        guard !unavailableIDs.isEmpty else { return 0 }
        let ids = Set(unavailableIDs)
        entries.removeAll { ids.contains($0.id) }
        scheduleSave()
        return unavailableIDs.count
    }

    func flush() { scheduleSave(delayNanoseconds: 0) }
    func dismissPersistenceError() { persistenceError = nil }

    private func load() {
        guard let repository else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self, repository] in
            defer { self?.loadTask = nil }
            let startedAt = Date()
            AppLog.history.info("History load started")
            do {
                let decoded = try await repository.load()
                try Task<Never, Never>.checkCancellation()
                guard let self else { return }
                let currentIDs = Set(self.entries.map(\.id))
                self.entries = Self.consolidated(
                    self.entries + decoded,
                    preferredIDs: currentIDs
                )
                self.hasFinishedInitialLoad = true
                self.scheduleSave(delayNanoseconds: 0)
                let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
                AppLog.history.info(
                    "History load succeeded duration_ms=\(duration, privacy: .public) entries=\(self.entries.count, privacy: .public)"
                )
            } catch is CancellationError {
                AppLog.history.debug("History load cancelled")
            } catch {
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
        entries.sort(by: Self.precedes)
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
        saveTask = Task { [weak self, repository] in
            do {
                if delayNanoseconds > 0 {
                    try await Task<Never, Never>.sleep(nanoseconds: delayNanoseconds)
                }
                try Task<Never, Never>.checkCancellation()
                try await repository.save(snapshot)
            } catch is CancellationError {
                return
            } catch {
                self?.persistenceError = .error(error, context: L10n.text("Unable to save history"))
            }
        }
    }

    static func consolidated(
        _ values: [SongHistoryEntry],
        preferredIDs: Set<UUID> = []
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
            if let migratedID = identifiedPathOwners[path]?.projectFileID { return "file:\(migratedID)" }
            return path.isEmpty ? "missing:\(entry.id.uuidString)" : path
        }
        return groups.values.compactMap { merge(Array($0), preferredIDs: preferredIDs) }
            .sorted(by: precedes)
    }

    private static func merge(
        _ group: [SongHistoryEntry],
        preferredIDs: Set<UUID>
    ) -> SongHistoryEntry? {
        let sorted = group.sorted { $0.updatedAt > $1.updatedAt }
        guard var merged = sorted.first(where: { preferredIDs.contains($0.id) }) ?? sorted.first else {
            return nil
        }
        let preferredSources = sorted.filter { preferredIDs.contains($0.id) }
        let sourcePool = preferredSources.isEmpty ? sorted : preferredSources
        let sourceOwner = sourcePool.max {
            sourceQuality($0.sourceLyrics) < sourceQuality($1.sourceLyrics)
        } ?? merged
        let locationOwner = sorted.first(where: {
            preferredIDs.contains($0.id) && ($0.projectFileID != nil || $0.projectBookmark != nil)
        }) ?? sorted.first(where: { $0.projectBookmark != nil })
            ?? sorted.first(where: { $0.projectFileID != nil })
            ?? sourceOwner
        merged.projectName = locationOwner.projectName.isEmpty
            ? sourceOwner.projectName : locationOwner.projectName
        merged.updateProjectLocation(
            path: normalizedProjectPath(locationOwner.projectPath),
            fileID: locationOwner.projectFileID,
            bookmark: locationOwner.projectBookmark
        )
        merged.updateSource(
            lyrics: sourceOwner.sourceLyrics,
            alternative: sourceOwner.alternative,
            bpm: sourceOwner.bpm ?? sorted.compactMap(\.bpm).first,
            musicalKey: sourceOwner.musicalKey ?? sorted.compactMap(\.musicalKey).first,
            diagnostics: sourceOwner.diagnostics,
            sourceStateToken: sourceOwner.sourceStateToken
        )
        merged.isPinned = sorted.contains(where: \.isPinned)
        merged.updatedAt = sorted.map(\.updatedAt).max() ?? merged.updatedAt
        return merged
    }

    private static func precedes(_ lhs: SongHistoryEntry, _ rhs: SongHistoryEntry) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        return lhs.updatedAt > rhs.updatedAt
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
        entries[index].projectName = location.url.deletingPathExtension().lastPathComponent
        entries[index].updateProjectLocation(
            path: Self.normalizedProjectPath(location.url.path),
            fileID: location.fileID,
            bookmark: location.bookmark ?? entries[index].projectBookmark
        )
        entries[index].updatedAt = Date()
        sortAndScheduleSave()
    }

    private static func sourceQuality(_ text: String) -> (Int, Int, Int) {
        (LyricSectionParser.parse(text).count, text.split(whereSeparator: \.isNewline).count, text.count)
    }
}
