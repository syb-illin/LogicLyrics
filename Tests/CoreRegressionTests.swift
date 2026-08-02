import AppKit
import Foundation

@main
enum CoreRegressionTests {
    @MainActor
    static func main() async throws {
        try testLyricSectionsAndDirectives()
        try testReaderErrors()
        try testReaderAlternativesMetadataAndDiagnostics()
        try testReaderCandidateQualityAndDefensiveRTF()
        try testHistorySearchPolicy()
        try testSchemaFiveEntryMigration()
        try await testHistoryRepositoryMigrationAndFailures()
        try testHistoryConsolidationAndManagement()
        try testProjectLocatorIdentityAndValidation()
        try await testProjectViewModelWorkflow()
        try await testUpdateServiceAndReleaseValidation()
        try testSemanticVersionComparison()
        print("Core regression tests: OK")
    }

    private static func testLyricSectionsAndDirectives() throws {
        let adjacent = LyricSectionParser.parse("[Verse 1]\nLine\n[Chorus][Outro]")
        try require(adjacent.map(\.label) == ["Verse 1", "Chorus", "Outro"], "Adjacent markers")
        try require(adjacent[0].fullText == "[Verse 1]\nLine", "Copyable section text")
        try require(LyricSectionParser.parse("No markers").isEmpty, "Unstructured lyrics")

        let directed = LyricSectionParser.parse(
            "[Verse 1]\n[male vocals]\nFirst line\n[clean guitar]\n[Chorus]\nHook"
        )
        try require(directed.map(\.label) == ["Verse 1", "Chorus"], "Suno directives are not sections")
        try require(directed[0].content.contains("[male vocals]"), "Vocal directive remains in body")
        try require(directed[0].content.contains("[clean guitar]"), "Production directive remains in body")

        let custom = LyricSectionParser.parse(" [Custom Part] \n Body \n[Empty]")
        try require(custom.count == 2 && custom[0].content == "Body", "Custom sections remain supported")
        try require(custom[1].content.isEmpty, "Empty structural section")
        try require(LyricSectionParser.parse("[female singing]\nInstruction only").isEmpty, "Standalone directive")
    }

    private static func testReaderErrors() throws {
        let reader = LogicProjectReader()
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try requireLogicError(.notLogicProject) {
            _ = try reader.readProject(at: root.appendingPathComponent("Song.txt"))
        }
        try requireLogicError(.unreadableProject) {
            _ = try reader.readProject(at: root.appendingPathComponent("Missing.logicx"))
        }
        let noAlternatives = root.appendingPathComponent("NoAlternatives.logicx", isDirectory: true)
        try FileManager.default.createDirectory(at: noAlternatives, withIntermediateDirectories: true)
        try requireLogicError(.alternativesMissing) { _ = try reader.readProject(at: noAlternatives) }

        let noData = root.appendingPathComponent("NoData.logicx", isDirectory: true)
        try FileManager.default.createDirectory(
            at: noData.appendingPathComponent("Alternatives/000", isDirectory: true),
            withIntermediateDirectories: true
        )
        try requireLogicError(.noProjectData) { _ = try reader.readProject(at: noData) }
        for error in [
            LogicProjectError.notLogicProject, .unreadableProject, .alternativesMissing, .noProjectData
        ] {
            try require(error.errorDescription?.isEmpty == false, "Localized reader errors")
        }
    }

    private static func testReaderAlternativesMetadataAndDiagnostics() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("Alternatives.logicx", isDirectory: true)
        try writeProjectData(["Old\nLyrics"], alternative: "001", project: project)
        try writeProjectData(["Active\nLyrics"], alternative: "007", project: project)
        try writeProjectData(["Named\nLyrics"], alternative: "custom", project: project)
        try writePlist(
            ["ActiveVariant": " 7 "],
            to: project.appendingPathComponent("Resources/ProjectInformation.plist")
        )
        try writePlist(
            ["BeatsPerMinute": 130.5, "SongKey": " F ", "SongGenderKey": "major"],
            to: project.appendingPathComponent("Alternatives/007/MetaData.plist")
        )

        let reader = LogicProjectReader()
        let active = try reader.readProject(at: project)
        try require(active.selectedAlternative == "007", "Active numeric alternative")
        try require(active.availableAlternatives == ["001", "007", "custom"], "All alternatives listed")
        try require(active.notes[0].text == "Active\nLyrics", "Active notes")
        try require(active.bpm == 130.5 && active.musicalKey == "F major", "Alternative metadata")
        try require(active.diagnostics.outcome == .selected, "Successful diagnostic")
        try require(active.diagnostics.selectedCandidateIndex == 0, "Selected RTF index")

        let named = try reader.readProject(at: project, preferredAlternative: "custom")
        try require(named.selectedAlternative == "custom", "Explicit alternative wins")
        try require(named.notes[0].text == "Named\nLyrics", "Explicit alternative notes")
        try require(named.bpm == nil && named.musicalKey == nil, "Missing metadata")
        try require(
            try reader.projectStateToken(at: project, preferredAlternative: "custom")
                == named.sourceStateToken,
            "Cheap source token matches read result"
        )

        let previousToken = named.sourceStateToken
        try "change".data(using: .utf8)?.appendTo(
            project.appendingPathComponent("Alternatives/custom/ProjectData")
        )
        let changedToken = try reader.projectStateToken(at: project, preferredAlternative: "custom")
        try require(changedToken != previousToken, "Source token detects disk change")

        let invalidMeta = root.appendingPathComponent("InvalidMeta.logicx", isDirectory: true)
        try writeProjectData(["Latest\nLyrics"], alternative: "009", project: invalidMeta)
        try writePlist(
            ["ActiveVariant": Date()],
            to: invalidMeta.appendingPathComponent("Resources/ProjectInformation.plist")
        )
        try writePlist(
            ["BeatsPerMinute": 999, "SongKey": " ", "SongGenderKey": ""],
            to: invalidMeta.appendingPathComponent("Alternatives/009/MetaData.plist")
        )
        let invalid = try reader.readProject(at: invalidMeta, preferredAlternative: "missing")
        try require(invalid.selectedAlternative == "009", "Safe fallback alternative")
        try require(invalid.bpm == nil && invalid.musicalKey == nil, "Invalid metadata rejected")

        let empty = root.appendingPathComponent("Empty.logicx", isDirectory: true)
        try writeRawProjectData(Data("binary only".utf8), alternative: "000", project: empty)
        let emptyResult = try reader.readProject(at: empty)
        try require(emptyResult.notes[0].isDraft, "No RTF creates an empty snapshot")
        try require(emptyResult.diagnostics.outcome == .noEmbeddedRichText, "No-RTF diagnostic")

        let undecodable = root.appendingPathComponent("Undecodable.logicx", isDirectory: true)
        try writeProjectData(["Readable\nText"], alternative: "000", project: undecodable)
        let decodeFailure = try LogicProjectReader(decodeRTFDocument: { _ in nil })
            .readProject(at: undecodable)
        try require(decodeFailure.diagnostics.outcome == .richTextCouldNotBeDecoded, "Decode diagnostic")

        let technical = root.appendingPathComponent("Technical.logicx", isDirectory: true)
        try writeProjectData(["Sample Library Loop 130"], alternative: "000", project: technical)
        let technicalResult = try reader.readProject(at: technical)
        try require(technicalResult.notes[0].isDraft, "Single-line technical RTF rejected")
        try require(technicalResult.diagnostics.outcome == .noLikelyProjectNotes, "Plausibility diagnostic")
    }

    private static func testReaderCandidateQualityAndDefensiveRTF() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("Quality.logicx", isDirectory: true)
        try writeProjectData(
            [
                "One\nTwo",
                "[Verse 1]\nLine",
                "[Verse 1]\nLine\n[Chorus]\nHook",
                "[Verse 1]\nLine\n[Chorus]\nA much longer hook"
            ],
            alternative: "000",
            project: project
        )
        let result = try LogicProjectReader().readProject(at: project)
        try require(result.notes[0].text.contains("longer hook"), "Quality tie-breakers")
        try require(result.diagnostics.decodedCandidateCount == 4, "Candidate count")

        let duplicate = root.appendingPathComponent("Duplicate.logicx", isDirectory: true)
        try writeProjectData(["", "Same\nLyrics", "Same\nLyrics"], alternative: "000", project: duplicate)
        let duplicateResult = try LogicProjectReader().readProject(at: duplicate)
        try require(duplicateResult.diagnostics.decodedCandidateCount == 1, "Empty and duplicates ignored")

        let incomplete = root.appendingPathComponent("Incomplete.logicx", isDirectory: true)
        try writeRawProjectData(Data("{\\rtf1 incomplete".utf8), alternative: "000", project: incomplete)
        try require(try LogicProjectReader().readProject(at: incomplete).notes[0].isDraft, "Incomplete RTF")
        try require(LogicProjectReader.decodeRTF(Data("not rtf".utf8)) == nil, "Malformed RTF")
        try require(!LogicProjectReader.matches([1, 2], in: Data([1]), at: 0), "Marker bound")
        try require(LogicProjectReader.advancePastControlSequence(in: Data("\\".utf8), from: 0) == 1, "Terminal escape")
        try require(LogicProjectReader.advancePastControlSequence(in: Data("\\{".utf8), from: 0) == 2, "Escaped brace")
        try require(LogicProjectReader.advancePastControlSequence(in: Data("\\bin-1 ".utf8), from: 0) == 7, "Negative binary")
        try require(LogicProjectReader.advancePastControlSequence(in: Data("\\bin2 ab".utf8), from: 0) == 8, "Binary payload")
    }

    private static func testHistorySearchPolicy() throws {
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let atLast = historyEntry(name: "at last", lyrics: "No title match", date: date)
        let lyricsOnly = historyEntry(name: "a myth", lyrics: "The last train", date: date)
        let empty = historyEntry(name: "instrumental", lyrics: " \n ", date: date)
        let entries = [atLast, lyricsOnly, empty]
        try require(HistorySearch.filter(entries, query: "", onlyWithoutLyrics: false) == entries, "Empty search")
        try require(HistorySearch.filter(entries, query: " LAST ", onlyWithoutLyrics: false).map(\.id) == [atLast.id], "Title-only search")
        try require(HistorySearch.filter(entries, query: "missing", onlyWithoutLyrics: false).isEmpty, "No search results")
        try require(HistorySearch.filter(entries, query: "", onlyWithoutLyrics: true).map(\.id) == [empty.id], "Missing lyrics filter")
        try require(HistorySearch.filter(entries, query: "last", onlyWithoutLyrics: true).isEmpty, "Composed filters")
    }

    private static func testSchemaFiveEntryMigration() throws {
        let id = UUID()
        let legacy: [String: Any] = [
            "id": id.uuidString,
            "projectName": "Legacy",
            "projectPath": "/tmp/Legacy.logicx",
            "alternative": "005",
            "sourceLyrics": "Verified Logic text",
            "editedLyrics": "Legacy local edit",
            "prompt": "Removed prompt",
            "referenceArtist": "Removed artist",
            "allowsFemaleBackingVocals": true,
            "createdAt": 100.0,
            "updatedAt": 200.0
        ]
        let entry = try JSONDecoder().decode(
            SongHistoryEntry.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        try require(entry.sourceLyrics == "Verified Logic text", "Verified source wins schema migration")
        try require(!entry.isPinned, "Legacy pin default")
        let encoded = try JSONEncoder().encode(entry)
        let string = String(decoding: encoded, as: UTF8.self)
        try require(!string.contains("prompt") && !string.contains("editedLyrics"), "Removed domains are not persisted")
        let roundTrip = try JSONDecoder().decode(SongHistoryEntry.self, from: encoded)
        try require(roundTrip == entry, "Schema 5 round trip")

        let veryOld: [String: Any] = ["lyrics": "Old text"]
        let oldEntry = try JSONDecoder().decode(
            SongHistoryEntry.self,
            from: JSONSerialization.data(withJSONObject: veryOld)
        )
        try require(oldEntry.sourceLyrics == "Old text", "Schema 1 lyrics fallback")
    }

    private static func testHistoryRepositoryMigrationAndFailures() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("LogicLyrics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history.json")
        let legacy: [String: Any] = [
            "schemaVersion": 4,
            "entries": [[
                "projectName": "Migrated",
                "projectPath": "/tmp/Migrated.logicx",
                "lyrics": "Legacy lyrics",
                "createdAt": 100.0,
                "updatedAt": 200.0
            ]]
        ]
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        let repository = try HistoryRepository(applicationSupportURL: root)
        let loaded = try await repository.load()
        try require(loaded.count == 1 && loaded[0].sourceLyrics == "Legacy lyrics", "Repository migration")
        try require(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("history-schema-4-backup.json").path),
            "Untouched schema backup"
        )
        try await repository.save(loaded)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        try require(saved?["schemaVersion"] as? Int == 5, "Schema 5 envelope")

        let bundleImport = directory.appendingPathComponent("history-legacy-bundle-import.json")
        try JSONSerialization.data(withJSONObject: [[
            "projectName": "Old Bundle",
            "projectPath": "/tmp/Old Bundle.logicx",
            "lyrics": "Imported lyrics",
            "createdAt": 50.0,
            "updatedAt": 60.0
        ]]).write(to: bundleImport)
        let mergedLoad = try await repository.load()
        try require(mergedLoad.count == 2, "Old bundle history is merged with schema 5")
        try await repository.save(mergedLoad)
        try require(!FileManager.default.fileExists(atPath: bundleImport.path), "Bundle import consumed after save")
        try require(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("history-legacy-bundle-backup.json").path),
            "Old bundle import preserved as backup"
        )

        let unsupported: [String: Any] = ["schemaVersion": 999, "entries": []]
        try JSONSerialization.data(withJSONObject: unsupported).write(to: file)
        do {
            _ = try await repository.load()
            throw TestFailure("Newer history schema must fail")
        } catch HistoryRepositoryError.unsupportedVersion(let version) {
            try require(version == 999, "Unsupported schema reports version")
        }

        try Data("invalid".utf8).write(to: file)
        do {
            _ = try await repository.load()
            throw TestFailure("Corrupt history must fail")
        } catch HistoryRepositoryError.corrupt(let backupName) {
            try require(backupName.hasPrefix("history-corrupt-"), "Corrupt backup name")
            try require(FileManager.default.fileExists(atPath: directory.appendingPathComponent(backupName).path), "Corrupt backup exists")
        }
    }

    @MainActor
    private static func testHistoryConsolidationAndManagement() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("Existing.logicx", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let missing = root.appendingPathComponent("Missing.logicx", isDirectory: true)
        let locator = TestProjectLocator(existingURLs: [existing])
        let old = SongHistoryEntry(
            id: UUID(), projectName: "Old", projectPath: existing.path,
            alternative: "001", sourceLyrics: "One\nTwo", bpm: 100, musicalKey: "C major",
            isPinned: true, createdAt: Date(), updatedAt: Date(), projectFileID: "stable"
        )
        let new = SongHistoryEntry(
            id: UUID(), projectName: "Renamed", projectPath: existing.path,
            alternative: "002", sourceLyrics: "[Verse 1]\nBetter\n[Chorus]\nHook",
            bpm: 120, musicalKey: "D minor", createdAt: Date(),
            updatedAt: Date().addingTimeInterval(10), projectFileID: "stable"
        )
        let consolidated = HistoryStore.consolidated([old, new], preferredIDs: [new.id])
        try require(consolidated.count == 1, "Filesystem identity consolidation")
        try require(consolidated[0].id == new.id && consolidated[0].isPinned, "Preferred identity and pin preserved")
        try require(consolidated[0].sourceLyrics.contains("Better"), "Preferred live source")

        let missingEntry = SongHistoryEntry(
            id: UUID(), projectName: "Missing", projectPath: missing.path,
            alternative: "000", sourceLyrics: "", bpm: nil, musicalKey: nil,
            createdAt: Date(), updatedAt: Date().addingTimeInterval(20)
        )
        let store = HistoryStore(inMemoryEntries: [new, missingEntry], locator: locator)
        store.togglePin(entryID: new.id)
        try require(store.entry(id: new.id)?.isPinned == true, "Pin action")
        try require(store.entries.first?.id == new.id, "Pinned rows sort first")
        try require(store.removeUnavailableProjects() == 1, "Missing project cleanup count")
        try require(store.entry(id: missingEntry.id) == nil, "Missing project removed")

        let result = LogicProjectReader.Result(
            notes: [ExtractedNote(alternative: "003", index: 0, text: "Updated\nLyrics")],
            bpm: 130,
            musicalKey: "F major",
            sourceStateToken: "updated"
        )
        let recordedID = store.recordProject(name: "Existing", url: existing, result: result)
        try require(recordedID == new.id, "Stable project updated rather than duplicated")
        try require(store.entry(id: new.id)?.sourceLyrics == "Updated\nLyrics", "History source refreshed")
        try require(try store.resolveProjectURL(entryID: new.id) == existing, "History resolves project")
        try require(try store.relocateProject(entryID: new.id, to: existing) == existing, "History relocates project")
        store.searchText = "existing"
        try require(store.filteredEntries.count == 1, "Store search projection")
        store.remove(entryID: new.id)
        try require(store.entries.isEmpty, "Single history removal")
        store.clear()
        store.dismissPersistenceError()
        store.flush()
    }

    private static func testProjectLocatorIdentityAndValidation() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Original.logicx", isDirectory: true)
        let renamed = root.appendingPathComponent("Renamed.logicx", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let locator = ProjectLocator()
        let captured = locator.capture(original)
        try require(captured.fileID != nil && captured.bookmark != nil, "Identity and bookmark captured")
        try FileManager.default.moveItem(at: original, to: renamed)
        let resolved = try locator.resolve(path: original.path, bookmark: captured.bookmark)
        try require(resolved.url == renamed.standardizedFileURL, "Bookmark follows rename")
        try require(resolved.fileID == captured.fileID, "Stable identity follows rename")

        let text = root.appendingPathComponent("Wrong.txt")
        try Data().write(to: text)
        do {
            _ = try locator.resolve(path: text.path, bookmark: nil)
            throw TestFailure("Non-Logic file must fail")
        } catch ProjectLocatorError.unavailable {
            try require(ProjectLocatorError.unavailable.errorDescription?.isEmpty == false, "Locator error localized")
            try require(ProjectLocatorError.invalidProject.errorDescription?.isEmpty == false, "Invalid error localized")
        }
    }

    @MainActor
    private static func testProjectViewModelWorkflow() async throws {
        let url = URL(fileURLWithPath: "/tmp/Workflow.logicx")
        let first = LogicProjectReader.Result(
            notes: [ExtractedNote(alternative: "001", index: 0, text: "[Verse 1]\nFirst")],
            bpm: 100,
            musicalKey: "C major",
            availableAlternatives: ["001", "002"],
            selectedAlternative: "001",
            sourceStateToken: "one"
        )
        let second = LogicProjectReader.Result(
            notes: [ExtractedNote(alternative: "002", index: 0, text: "[Chorus]\nSecond")],
            bpm: 120,
            musicalKey: "D minor",
            availableAlternatives: ["001", "002"],
            selectedAlternative: "002",
            sourceStateToken: "two"
        )
        let reader = TestLogicReader(results: ["001": first, "002": second], fallback: first)
        let model = ProjectViewModel(reader: reader)
        var loadedCount = 0
        model.onProjectLoaded = { _, _, _ in loadedCount += 1 }
        model.open(url, preferredAlternative: "001")
        try await waitUntil { !model.isLoading }
        try require(model.projectName == "Workflow", "View model project name")
        try require(model.selectedNote?.text.contains("First") == true, "Initial lyrics")
        try require(model.sections.count == 1 && loadedCount == 1, "Sections and observer")
        try require(model.availableAlternatives == ["001", "002"], "Alternative presentation")

        model.selectAlternative("missing")
        try require(!model.isLoading, "Unknown alternative ignored")
        model.selectAlternative("001")
        try require(!model.isLoading, "Selected alternative ignored")
        model.selectAlternative("002")
        try await waitUntil { !model.isLoading }
        try require(model.selectedAlternativeName == "002", "Alternative switch")
        try require(model.bpm == 120 && model.musicalKey == "D minor", "Alternative metadata switch")

        reader.currentToken = "changed"
        model.checkForExternalChanges()
        try await waitUntil { model.isSourceModified }
        model.refresh()
        try await waitUntil { !model.isLoading }
        try require(!model.isSourceModified, "Refresh clears stale state")

        reader.error = LogicProjectError.unreadableProject
        model.refresh()
        try await waitUntil { !model.isLoading }
        try require(model.errorMessage != nil, "Refresh error visible")
        try require(model.selectedNote?.text.contains("Second") == true, "Failed refresh preserves snapshot")
        model.cancelProcessing()

        let failing = ProjectViewModel(reader: TestLogicReader(error: LogicProjectError.unreadableProject))
        failing.open(url)
        try await waitUntil { !failing.isLoading }
        try require(failing.projectURL == nil && failing.notes.isEmpty, "Initial failure clears document")
    }

    @MainActor
    private static func testUpdateServiceAndReleaseValidation() async throws {
        let valid = updateRelease(version: "99.0.0")
        try UpdateService.validate(valid)
        for invalid in [
            UpdateRelease(version: "", sourceArchiveURL: valid.sourceArchiveURL, sourceChecksumURL: valid.sourceChecksumURL, releasePageURL: nil, releaseNotes: ""),
            UpdateRelease(version: "99.0.0", sourceArchiveURL: URL(string: "https://evil.example/file.zip"), sourceChecksumURL: valid.sourceChecksumURL, releasePageURL: nil, releaseNotes: "")
        ] {
            do {
                try UpdateService.validate(invalid)
                throw TestFailure("Invalid release must fail")
            } catch is UpdateService.UpdateError {}
        }

        let available = UpdateService(releaseClient: TestReleaseClient(result: .success(valid)))
        available.check(silent: false)
        try await waitUntil { available.state != .checking }
        try require(available.state == .available(version: "99.0.0"), "Available update state")
        try require(available.availableRelease == valid, "Verified release retained")

        let current = UpdateService(releaseClient: TestReleaseClient(result: .success(updateRelease(version: "0.0.0"))))
        current.check(silent: false)
        try await waitUntil { current.state != .checking }
        try require(current.state == .current, "Current update state")

        let failure = UpdateService(releaseClient: TestReleaseClient(result: .failure(URLError(.notConnectedToInternet))))
        failure.check(silent: false)
        try await waitUntil { failure.state != .checking }
        try require(failure.state == .idle && failure.errorMessage != nil, "Manual update error")
    }

    private static func testSemanticVersionComparison() throws {
        try require(UpdateService.isNewer("2.6.1", than: "2.6.0"), "Patch comparison")
        try require(UpdateService.isNewer("2.10.0", than: "2.9.9"), "Minor comparison")
        try require(UpdateService.isNewer("3.0", than: "2.99.99"), "Major comparison")
        try require(!UpdateService.isNewer("2.6.0", than: "2.6.0"), "Equal comparison")
        try require(!UpdateService.isNewer("2.5.9", than: "2.6.0"), "Older comparison")
        try require(!UpdateService.isNewer("3.beta", than: "2.6.0"), "Invalid comparison")
        try require(!UpdateService.isNewer("3..0", than: "2.6.0"), "Empty component")
    }

    private static func updateRelease(version: String) -> UpdateRelease {
        let base = "https://github.com/syb-illin/LogicLyrics/releases/download/v\(version)"
        return UpdateRelease(
            version: version,
            sourceArchiveURL: URL(string: "\(base)/LogicLyrics-macOS-source.zip"),
            sourceChecksumURL: URL(string: "\(base)/LogicLyrics-macOS-source.zip.sha256"),
            releasePageURL: URL(string: "https://github.com/syb-illin/LogicLyrics/releases/tag/v\(version)"),
            releaseNotes: "Test release"
        )
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func writeProjectData(_ texts: [String], alternative: String, project: URL) throws {
        let url = project.appendingPathComponent("Alternatives/\(alternative)/ProjectData")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data("synthetic Logic fixture".utf8)
        for text in texts {
            let attributed = NSAttributedString(string: text)
            data.append(try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ))
        }
        try data.write(to: url)
    }

    private static func writeRawProjectData(_ data: Data, alternative: String, project: URL) throws {
        let url = project.appendingPathComponent("Alternatives/\(alternative)/ProjectData")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private static func writePlist(_ values: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            .write(to: url)
    }

    private static func historyEntry(name: String, lyrics: String, date: Date) -> SongHistoryEntry {
        SongHistoryEntry(
            id: UUID(), projectName: name, projectPath: "/tmp/\(name).logicx",
            alternative: "000", sourceLyrics: lyrics, bpm: nil, musicalKey: nil,
            createdAt: date, updatedAt: date
        )
    }

    @MainActor
    private static func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { throw TestFailure("Timed out waiting for asynchronous state") }
            try await Task<Never, Never>.sleep(nanoseconds: 10_000_000)
        }
    }

    private static func requireLogicError(
        _ expected: LogicProjectError,
        operation: () throws -> Void
    ) throws {
        do { try operation() }
        catch let error as LogicProjectError {
            try require(error == expected, "Expected \(expected), received \(error)")
            return
        }
        throw TestFailure("Expected LogicProjectError")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(message) }
    }
}

private struct TestFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private extension Data {
    func appendTo(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: self)
    }
}

private final class TestLogicReader: LogicProjectReading, @unchecked Sendable {
    private let lock = NSLock()
    private let results: [String: LogicProjectReader.Result]
    private let fallback: LogicProjectReader.Result?
    var currentToken: String
    var error: Error?

    init(
        results: [String: LogicProjectReader.Result] = [:],
        fallback: LogicProjectReader.Result? = nil,
        error: Error? = nil
    ) {
        self.results = results
        self.fallback = fallback
        currentToken = fallback?.sourceStateToken ?? "stub"
        self.error = error
    }

    func readProject(at projectURL: URL) throws -> LogicProjectReader.Result {
        try readProject(at: projectURL, preferredAlternative: nil)
    }

    func readProject(at projectURL: URL, preferredAlternative: String?) throws -> LogicProjectReader.Result {
        lock.lock()
        defer { lock.unlock() }
        if let error { throw error }
        if let preferredAlternative, let result = results[preferredAlternative] {
            currentToken = result.sourceStateToken
            return result
        }
        guard let fallback else { throw LogicProjectError.unreadableProject }
        currentToken = fallback.sourceStateToken
        return fallback
    }

    func projectStateToken(at projectURL: URL, preferredAlternative: String?) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if let error { throw error }
        return currentToken
    }
}

private final class TestProjectLocator: ProjectLocating, @unchecked Sendable {
    private let existingPaths: Set<String>

    init(existingURLs: [URL]) {
        existingPaths = Set(existingURLs.map { $0.standardizedFileURL.path })
    }

    func capture(_ url: URL) -> ProjectLocation {
        ProjectLocation(url: url.standardizedFileURL, fileID: "stable", bookmark: Data([1]))
    }

    func resolve(path: String, bookmark: Data?) throws -> ProjectLocation {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard existingPaths.contains(url.path) else { throw ProjectLocatorError.unavailable }
        return capture(url)
    }
}

private struct TestReleaseClient: UpdateReleaseChecking {
    let result: Result<UpdateRelease, Error>
    func latestRelease() async throws -> UpdateRelease { try result.get() }
}
