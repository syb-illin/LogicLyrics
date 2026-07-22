import AppKit
import Foundation

@main
enum CoreRegressionTests {
    @MainActor
    static func main() async throws {
        try testAdjacentSections()
        try testLegacyHistoryMigration()
        try testHistoryDeduplicatesLegacyProjectRows()
        try testHistorySeparatesSourceEditsAndRecoveredText()
        try testHistoryStartupMergePrefersLiveProject()
        try testHistoryRevisionRestoreAndRevert()
        try testHistoryIdentitySurvivesMove()
        try testHistoryConsolidatesRenamedProjectIdentity()
        try testPortableHistoryArchiveRoundTrip()
        try testLogicSourceProtection()
        try testLogicEmptyNoteCreation()
        try testActiveLogicProjectNotesSelection()
        try testTechnicalRichTextIsNotLyrics()
        try await testHistoryObserverCannotReplaceLiveLyrics()
        try testID3v24RoundTripAndPreservation()
        try testSemanticVersionComparison()
        print("Core regression tests: OK")
    }

    private static func testAdjacentSections() throws {
        let sections = LyricSectionParser.parse("[Verse 1]\nLine\n[Chorus][Outro]")
        try require(sections.map(\.label) == ["Verse 1", "Chorus", "Outro"], "Adjacent Suno markers")
    }

    private static func testLegacyHistoryMigration() throws {
        let id = UUID()
        let legacy: [String: Any] = [
            "id": id.uuidString,
            "projectName": "Legacy",
            "projectPath": "/tmp/Legacy.logicx",
            "lyrics": "Text",
            "prompt": "",
            "referenceArtist": "",
            "allowsFemaleBackingVocals": false,
            "createdAt": Date().timeIntervalSinceReferenceDate,
            "updatedAt": Date().timeIntervalSinceReferenceDate
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let entry = try JSONDecoder().decode(SongHistoryEntry.self, from: data)
        try require(entry.noteKey == "legacy", "Legacy history note key")
        try require(entry.sourceLyrics == "Text", "Legacy lyrics retained as source")
        try require(entry.needsSourceReconciliation, "Legacy source requires reconciliation")
    }

    @MainActor
    private static func testHistoryDeduplicatesLegacyProjectRows() throws {
        let path = "/tmp/Album/../Album/Plaid.logicx"
        let technical = try legacyHistoryEntry(
            id: UUID(), path: path, noteKey: "005#0",
            lyrics: "Sample Library - Indie Rock Drum Loop 130",
            prompt: "", updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let projectNotes = try legacyHistoryEntry(
            id: UUID(), path: "/tmp/Album/Plaid.logicx", noteKey: "005#2",
            lyrics: "Demo Song\n[Verse 1]\nFirst lyric line\n[Chorus]\nSecond lyric line",
            prompt: "Saved Suno prompt", updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )

        let consolidated = HistoryStore.consolidated([technical, projectNotes])
        try require(consolidated.count == 1, "One history row per Logic project")
        let entry = try requireValue(consolidated.first, "Consolidated history entry")
        try require(entry.sourceLyrics.contains("First lyric line"), "Rich Project Notes win over technical RTF")
        try require(entry.prompt == "Saved Suno prompt", "Prompt preserved during deduplication")
        try require(entry.recoveredLyrics.contains("Sample Library - Indie Rock Drum Loop 130"), "Discarded legacy text recovered")
        try require(entry.needsSourceReconciliation, "Deduplicated legacy source remains unverified")
    }

    private static func testHistorySeparatesSourceEditsAndRecoveredText() throws {
        var entry = try legacyHistoryEntry(
            id: UUID(), path: "/tmp/Song.logicx", noteKey: "legacy",
            lyrics: "Previous saved lyrics", prompt: "", updatedAt: Date()
        )
        entry.reconcileSourceLyrics("[Verse 1]\nCurrent Logic lyrics")
        entry.applyLocalEdit("[Verse 1]\nLocally edited lyrics")
        entry.reconcileSourceLyrics("[Verse 1]\nUpdated Logic lyrics")

        try require(entry.sourceLyrics.contains("Updated Logic"), "Latest Logic source stored separately")
        try require(entry.editedLyrics?.contains("Locally edited") == true, "Local edit preserved across source refresh")
        try require(entry.lyrics == "[Verse 1]\nLocally edited lyrics", "History favors the local edit")
        try require(entry.recoveredLyrics.contains("Previous saved lyrics"), "Legacy text preserved without becoming current")
        try require(entry.recoveredLyrics.contains("[Verse 1]\nCurrent Logic lyrics"), "Previous source revision preserved")

        let roundTrip = try JSONDecoder().decode(SongHistoryEntry.self, from: JSONEncoder().encode(entry))
        try require(roundTrip == entry, "History schema 4 round trip")
    }

    private static func testHistoryRevisionRestoreAndRevert() throws {
        var entry = SongHistoryEntry(
            id: UUID(), projectName: "Restore", projectPath: "/tmp/Restore.logicx",
            noteKey: "000#1", alternative: "000", lyrics: "Project source",
            prompt: "", referenceArtist: "", allowsFemaleBackingVocals: false,
            bpm: nil, musicalKey: nil, createdAt: Date(), updatedAt: Date()
        )
        entry.applyLocalEdit("First edit")
        entry.recover("Older revision")
        entry.restoreRevision("Older revision")
        try require(entry.editedLyrics == "Older revision", "Recovered revision becomes the local edit")
        try require(entry.recoveredLyrics.contains("First edit"), "Replaced edit remains recoverable")
        entry.revertToSource()
        try require(entry.editedLyrics == nil && entry.lyrics == "Project source", "Revert restores Logic source")
        try require(entry.recoveredLyrics.contains("Older revision"), "Reverted edit remains recoverable")
    }

    private static func testHistoryIdentitySurvivesMove() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let original = root.appendingPathComponent("Original.logicx", isDirectory: true)
        let renamed = root.appendingPathComponent("Renamed.logicx", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let locator = ProjectLocator()
        let captured = locator.capture(original)
        try require(captured.fileID != nil, "Stable filesystem identity captured")
        try require(captured.bookmark != nil, "Project bookmark captured")
        try FileManager.default.moveItem(at: original, to: renamed)
        let resolved = try locator.resolve(path: original.path, bookmark: captured.bookmark)
        try require(resolved.url.standardizedFileURL == renamed.standardizedFileURL, "Bookmark follows renamed project")
        try require(resolved.fileID == captured.fileID, "Filesystem identity survives rename")
    }

    @MainActor
    private static func testHistoryConsolidatesRenamedProjectIdentity() throws {
        let fileID = "volume:file"
        let old = SongHistoryEntry(
            id: UUID(), projectName: "Old", projectPath: "/tmp/Old.logicx",
            noteKey: "000#1", alternative: "000", lyrics: "Old source",
            prompt: "Saved prompt", referenceArtist: "", allowsFemaleBackingVocals: false,
            bpm: 120, musicalKey: "C major", createdAt: Date(), updatedAt: Date(),
            projectFileID: fileID, projectBookmark: Data([1, 2, 3])
        )
        let new = SongHistoryEntry(
            id: UUID(), projectName: "Renamed", projectPath: "/tmp/Renamed.logicx",
            noteKey: "000#1", alternative: "000", lyrics: "Current source",
            prompt: "", referenceArtist: "", allowsFemaleBackingVocals: false,
            bpm: 121, musicalKey: "D minor", createdAt: Date(),
            updatedAt: Date().addingTimeInterval(10), projectFileID: fileID,
            projectBookmark: Data([4, 5, 6])
        )

        let values = HistoryStore.consolidated([old, new], preferredIDs: [new.id])
        let entry = try requireValue(values.first, "Renamed project consolidation")
        try require(values.count == 1, "Moved project keeps one history row")
        try require(entry.id == new.id && entry.projectName == "Renamed", "Newest project location wins")
        try require(entry.projectPath == "/tmp/Renamed.logicx", "Renamed path is persisted")
        try require(entry.prompt == "Saved prompt", "Prompt survives project rename")
    }

    private static func testPortableHistoryArchiveRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archiveURL = root.appendingPathComponent("History.\(HistoryArchiveService.fileExtension)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var entry = SongHistoryEntry(
            id: UUID(), projectName: "Portable", projectPath: "/tmp/Portable.logicx",
            noteKey: "001#2", alternative: "001", lyrics: "Project lyrics",
            prompt: "Saved prompt", referenceArtist: "Band", allowsFemaleBackingVocals: true,
            bpm: 128, musicalKey: "E minor", createdAt: Date(), updatedAt: Date(),
            projectFileID: "machine-specific", projectBookmark: Data([7, 8, 9])
        )
        entry.applyLocalEdit("Edited lyrics")
        entry.recover("Recovered lyrics")

        let service = HistoryArchiveService()
        try service.write([entry], to: archiveURL)
        let imported = try service.read(from: archiveURL)
        let decoded = try requireValue(imported.first, "Portable archive entry")
        try require(imported.count == 1, "Portable archive count")
        try require(decoded.sourceLyrics == "Project lyrics", "Archive preserves Logic source")
        try require(decoded.editedLyrics == "Edited lyrics", "Archive preserves local edit")
        try require(decoded.recoveredLyrics == ["Recovered lyrics"], "Archive preserves revisions")
        try require(decoded.prompt == "Saved prompt", "Archive preserves prompt")
        try require(decoded.projectFileID == nil && decoded.projectBookmark == nil, "Archive strips Mac capabilities")
    }

    @MainActor
    private static func testHistoryStartupMergePrefersLiveProject() throws {
        let live = SongHistoryEntry(
            id: UUID(), projectName: "Plaid", projectPath: "/tmp/Plaid.logicx",
            noteKey: "005#2", alternative: "005",
            lyrics: "Demo Song\n[Verse 1]\nLive project lyrics", prompt: "",
            referenceArtist: "", allowsFemaleBackingVocals: false,
            bpm: 130, musicalKey: "F major", createdAt: Date(), updatedAt: Date()
        )
        let cached = try legacyHistoryEntry(
            id: UUID(), path: "/tmp/Plaid.logicx", noteKey: "005#1",
            lyrics: "Sample Library - Indie Rock", prompt: "Existing prompt",
            updatedAt: Date().addingTimeInterval(60)
        )

        let merged = HistoryStore.consolidated([cached, live], preferredIDs: [live.id])
        let entry = try requireValue(merged.first, "Startup-merged history entry")
        try require(entry.id == live.id, "Active UI history identity remains stable")
        try require(entry.sourceLyrics == live.sourceLyrics, "Live project wins asynchronous startup race")
        try require(entry.prompt == "Existing prompt", "Existing prompt survives startup merge")
        try require(entry.recoveredLyrics.contains("Sample Library - Indie Rock"), "Stale cache retained only as recovered text")
    }

    private static func testLogicSourceProtection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("Original.logicx", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try LogicProjectWriter().createEditedCopy(
                source: project, destination: project, alternative: "000", originalText: "a", editedText: "b"
            )
            throw TestFailure("Source equals destination was accepted")
        } catch LogicProjectWriteError.sourceEqualsDestination {
            try require(FileManager.default.fileExists(atPath: project.path), "Original project preserved")
        }
    }

    private static func testLogicEmptyNoteCreation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("Empty.logicx", isDirectory: true)
        let projectData = source.appendingPathComponent("Alternatives/000/ProjectData")
        let destination = root.appendingPathComponent("With-Lyrics.logicx", isDirectory: true)
        try FileManager.default.createDirectory(at: projectData.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var emptyRecord = Data(repeating: 0, count: 98)
        setLittleEndianUInt32(98, in: &emptyRecord, at: 0)
        setLittleEndianUInt32(98, in: &emptyRecord, at: 16)
        setLittleEndianUInt32(98, in: &emptyRecord, at: 20)
        emptyRecord.replaceSubrange(24..<36, with: Data([0x13, 0, 0xFF, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0]))
        try emptyRecord.write(to: projectData)

        let reader = LogicProjectReader()
        let initial = try reader.readProject(at: source)
        try require(initial.notes.count == 1 && initial.notes[0].isDraft, "Empty Logic note draft")
        try LogicProjectWriter().createEditedCopy(
            source: source, destination: destination, alternative: "000",
            originalText: "", editedText: "[Verse 1]\nNew lyrics"
        )
        let written = try reader.readProject(at: destination)
        try require(written.notes.first?.text == "[Verse 1]\nNew lyrics", "Empty Logic note insertion")
        let originalProjectData = try Data(contentsOf: projectData)
        try require(originalProjectData.count == 98, "Empty Logic source preserved")
    }

    private static func testActiveLogicProjectNotesSelection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("Selection.logicx", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try writeProjectData(
            ["[Verse 1]\nStale alternative"],
            alternative: "000",
            project: project
        )
        try writeProjectData(
            [
                "Sample Library - Indie Rock Drum Loop 130",
                "Demo Song\nVerse 1\nFirst lyric line\nChorus\nSecond lyric line",
                "Sample Library - Indie Rock Drum Loop 130 Alternate"
            ],
            alternative: "005",
            project: project
        )
        try writePlist(
            ["ActiveVariant": 5],
            to: project.appendingPathComponent("Resources/ProjectInformation.plist")
        )
        try writePlist(
            ["BeatsPerMinute": 130.0, "SongKey": "F", "SongGenderKey": "major"],
            to: project.appendingPathComponent("Alternatives/005/MetaData.plist")
        )

        let result = try LogicProjectReader().readProject(at: project)
        try require(result.notes.count == 1, "Only Project Notes selected")
        try require(result.notes[0].alternative == "005", "Active Logic alternative selected")
        try require(result.notes[0].index == 1, "Project Notes keep their stable RTF index")
        try require(result.notes[0].text.contains("First lyric line"), "Active lyrics extracted")
        try require(result.bpm == 130 && result.musicalKey == "F major", "Active alternative metadata")
    }

    private static func testTechnicalRichTextIsNotLyrics() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("No-Lyrics.logicx", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeProjectData(
            ["Sample Library - Indie Rock Drum Loop 130"],
            alternative: "000",
            project: project
        )

        let result = try LogicProjectReader().readProject(at: project)
        try require(result.notes.count == 1 && result.notes[0].isDraft, "Technical RTF rejected as lyrics")
    }

    @MainActor
    private static func testHistoryObserverCannotReplaceLiveLyrics() async throws {
        let liveLyrics = "Demo Song\n[Verse 1]\nLyrics from the currently open Logic project"
        let note = ExtractedNote(alternative: "005", index: 1, text: liveLyrics)
        let result = LogicProjectReader.Result(notes: [note], bpm: 130, musicalKey: "F major")
        let model = ProjectViewModel(reader: StubLogicProjectReader(result: result))
        let cachedHistoryLyrics = "Sample Library - Indie Rock Drum Loop 130"
        var observedLyrics: String?
        model.onProjectLoaded = { _, _, notes, _, _ in
            // History can observe the source but has no return channel through
            // which its stale cached value can replace the current project.
            observedLyrics = notes.first?.text
        }

        model.open(URL(fileURLWithPath: "/tmp/Selection.logicx"))
        for _ in 0..<300 {
            if !model.isLoading { break }
            try await Task<Never, Never>.sleep(nanoseconds: 10_000_000)
        }

        try require(!model.isLoading, "Project view model load completed")
        try require(cachedHistoryLyrics != liveLyrics, "Regression fixture contains stale history")
        try require(observedLyrics == liveLyrics, "History observed the extracted lyrics")
        try require(model.selectedNote?.text == liveLyrics, "Live project lyrics remain the editor source")
        try require(model.sections.count == 1, "Live lyrics drive section parsing")
    }

    private static func testID3v24RoundTripAndPreservation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mp3")
        let output = root.appendingPathComponent("output.mp3")

        var unknownPayload = Data([3]); unknownPayload.append(Data("LAME test".utf8))
        let unknownFrame = id3v24Frame("TSSE", payload: unknownPayload)
        var tag = Data("ID3".utf8); tag.append(contentsOf: [4, 0, 0])
        tag.append(contentsOf: synchsafe(unknownFrame.count)); tag.append(unknownFrame)
        tag.append(contentsOf: [0xFF, 0xFB, 0x90, 0x64, 0, 0, 0, 0])
        try tag.write(to: source)

        let metadata = AudioMetadata(
            title: "Blue Æther", trackNumber: "01", artist: "wake up fall", album: "Test",
            year: 2026, genre: "Alternative", bpm: 140, lyrics: "Lyrics", artwork: nil, artworkMIMEType: nil
        )
        try AudioMetadataWriter().write(source: source, destination: output, metadata: metadata)
        let bytes = try Data(contentsOf: output)
        try require(bytes.count > 10 && bytes[3] == 4, "ID3v2.4 header")
        try require(bytes.range(of: Data("TSSE".utf8)) != nil, "Unknown ID3 frame preserved")
        let decoded = try AudioMetadataReader().read(from: output)
        try require(decoded.title == "Blue Æther" && decoded.artist == "wake up fall", "Unicode ID3 round trip")
    }

    private static func testSemanticVersionComparison() throws {
        try require(UpdateService.isNewer("2.2.1", than: "2.2.0"), "Patch update comparison")
        try require(UpdateService.isNewer("2.10.0", than: "2.9.9"), "Numeric minor version comparison")
        try require(UpdateService.isNewer("3.0", than: "2.99.99"), "Major version comparison")
        try require(!UpdateService.isNewer("2.2.0", than: "2.2.0"), "Equal version comparison")
        try require(!UpdateService.isNewer("2.1.9", than: "2.2.0"), "Older version comparison")
        try require(!UpdateService.isNewer("3.beta", than: "2.2.0"), "Invalid version rejection")
        try require(!UpdateService.isNewer("3..0", than: "2.2.0"), "Empty version component rejection")
    }

    private static func id3v24Frame(_ id: String, payload: Data) -> Data {
        var data = Data(id.utf8)
        data.append(contentsOf: synchsafe(payload.count))
        data.append(contentsOf: [0, 0]); data.append(payload)
        return data
    }

    private static func synchsafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 127), UInt8((value >> 14) & 127), UInt8((value >> 7) & 127), UInt8(value & 127)]
    }

    private static func setLittleEndianUInt32(_ value: UInt32, in data: inout Data, at offset: Int) {
        let bytes = withUnsafeBytes(of: value.littleEndian) { Data($0) }
        data.replaceSubrange(offset..<(offset + 4), with: bytes)
    }

    private static func writeProjectData(_ texts: [String], alternative: String, project: URL) throws {
        let url = project.appendingPathComponent("Alternatives/\(alternative)/ProjectData")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data("synthetic Logic fixture".utf8)
        for text in texts {
            let attributed = NSAttributedString(string: text)
            let rtf = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            data.append(rtf)
        }
        try data.write(to: url)
    }

    private static func writePlist(_ values: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try data.write(to: url)
    }

    private static func legacyHistoryEntry(
        id: UUID, path: String, noteKey: String, lyrics: String,
        prompt: String, updatedAt: Date
    ) throws -> SongHistoryEntry {
        let legacy: [String: Any] = [
            "id": id.uuidString,
            "projectName": "Plaid",
            "projectPath": path,
            "noteKey": noteKey,
            "alternative": "005",
            "lyrics": lyrics,
            "prompt": prompt,
            "referenceArtist": "",
            "allowsFemaleBackingVocals": false,
            "createdAt": Date(timeIntervalSinceReferenceDate: 50).timeIntervalSinceReferenceDate,
            "updatedAt": updatedAt.timeIntervalSinceReferenceDate
        ]
        return try JSONDecoder().decode(
            SongHistoryEntry.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
    }

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestFailure(message) }
        return value
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

private struct StubLogicProjectReader: LogicProjectReading {
    let result: LogicProjectReader.Result

    func readProject(at projectURL: URL) throws -> LogicProjectReader.Result {
        result
    }
}
