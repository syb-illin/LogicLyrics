import AppKit
import Foundation

@main
enum CoreRegressionTests {
    @MainActor
    static func main() async throws {
        try testAdjacentSections()
        try testLyricSectionParserEdges()
        try testReaderErrors()
        try testReaderAlternativeAndMetadataEdges()
        try testReaderQualityTieBreakers()
        try testReaderDecodeFailureFallsBackToDraft()
        try testReaderDefensiveRTFBranches()
        try testHistorySearchPolicy()
        try testLegacyHistoryMigration()
        try testHistoryDeduplicatesLegacyProjectRows()
        try testHistorySeparatesSourceEditsAndRecoveredText()
        try testHistoryStartupMergePrefersLiveProject()
        try testHistoryRevisionRestoreAndRevert()
        try testHistoryIdentitySurvivesMove()
        try testHistoryConsolidatesRenamedProjectIdentity()
        try testActiveLogicProjectNotesSelection()
        try testTechnicalRichTextIsNotLyrics()
        try await testHistoryObserverCannotReplaceLiveLyrics()
        try testSemanticVersionComparison()
        print("Core regression tests: OK")
    }

    private static func testAdjacentSections() throws {
        let sections = LyricSectionParser.parse("[Verse 1]\nLine\n[Chorus][Outro]")
        try require(sections.map(\.label) == ["Verse 1", "Chorus", "Outro"], "Adjacent section markers")
        try require(sections[0].fullText == "[Verse 1]\nLine", "A section reconstructs copyable text")
    }

    private static func testLyricSectionParserEdges() throws {
        try require(LyricSectionParser.parse("No markers here").isEmpty, "Unstructured lyrics have no sections")
        let sections = LyricSectionParser.parse("  [Custom Part]  \n  Body line  \n[Empty]")
        try require(sections.count == 2, "Custom and empty sections are retained")
        try require(sections[0].label == "Custom Part" && sections[0].content == "Body line", "Section text is trimmed")
        try require(sections[1].content.isEmpty, "An empty final section is valid")
    }

    private static func testReaderErrors() throws {
        let reader = LogicProjectReader()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try requireLogicError(.notLogicProject) {
            _ = try reader.readProject(at: root.appendingPathComponent("Song.txt"))
        }
        try requireLogicError(.unreadableProject) {
            _ = try reader.readProject(at: root.appendingPathComponent("Missing.logicx"))
        }

        let noAlternatives = root.appendingPathComponent("No-Alternatives.logicx", isDirectory: true)
        try FileManager.default.createDirectory(at: noAlternatives, withIntermediateDirectories: true)
        try requireLogicError(.alternativesMissing) {
            _ = try reader.readProject(at: noAlternatives)
        }

        let noProjectData = root.appendingPathComponent("No-ProjectData.logicx", isDirectory: true)
        try FileManager.default.createDirectory(
            at: noProjectData.appendingPathComponent("Alternatives/000", isDirectory: true),
            withIntermediateDirectories: true
        )
        try requireLogicError(.noProjectData) {
            _ = try reader.readProject(at: noProjectData)
        }

        for error in [
            LogicProjectError.notLogicProject,
            .alternativesMissing,
            .noProjectData,
            .unreadableProject
        ] {
            try require(error.errorDescription?.isEmpty == false, "Reader errors are localized for the user")
        }
    }

    private static func testReaderAlternativeAndMetadataEdges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let numeric = root.appendingPathComponent("Numeric.logicx", isDirectory: true)
        try writeProjectData(["Wrong\nAlternative"], alternative: "009", project: numeric)
        try writeProjectData(["Numeric\nSelection"], alternative: "007", project: numeric)
        try writePlist(["ActiveVariant": " 7 "], to: numeric.appendingPathComponent("Resources/ProjectInformation.plist"))
        let numericResult = try LogicProjectReader().readProject(at: numeric)
        try require(numericResult.notes[0].alternative == "007", "Numeric string alternative is normalized")

        let named = root.appendingPathComponent("Named.logicx", isDirectory: true)
        try writeProjectData(["Wrong\nAlternative"], alternative: "zzz", project: named)
        try writeProjectData(["Named\nSelection"], alternative: "custom", project: named)
        try writePlist(["ActiveVariant": " custom "], to: named.appendingPathComponent("Resources/ProjectInformation.plist"))
        let namedResult = try LogicProjectReader().readProject(at: named)
        try require(namedResult.notes[0].alternative == "custom", "Named alternative is selected")

        let fallback = root.appendingPathComponent("Fallback.logicx", isDirectory: true)
        try writeProjectData(["First\nAlternative"], alternative: "001", project: fallback)
        try writeProjectData(["Latest\nAlternative"], alternative: "009", project: fallback)
        try writePlist(["ActiveVariant": "   "], to: fallback.appendingPathComponent("Resources/ProjectInformation.plist"))
        try writePlist(
            ["BeatsPerMinute": 999, "SongKey": " ", "SongGenderKey": ""],
            to: fallback.appendingPathComponent("Alternatives/009/MetaData.plist")
        )
        let fallbackResult = try LogicProjectReader().readProject(at: fallback)
        try require(fallbackResult.notes[0].alternative == "009", "Blank alternative falls back to the latest project data")
        try require(fallbackResult.bpm == nil && fallbackResult.musicalKey == nil, "Invalid metadata is omitted")

        let unsupported = root.appendingPathComponent("Unsupported.logicx", isDirectory: true)
        try writeProjectData(["Latest\nAlternative"], alternative: "003", project: unsupported)
        try writePlist(["ActiveVariant": Date()], to: unsupported.appendingPathComponent("Resources/ProjectInformation.plist"))
        let unsupportedResult = try LogicProjectReader().readProject(at: unsupported)
        try require(unsupportedResult.notes[0].alternative == "003", "Unsupported alternative metadata falls back safely")
    }

    private static func testReaderQualityTieBreakers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let markers = root.appendingPathComponent("Markers.logicx", isDirectory: true)
        try writeProjectData(
            ["[Verse 1]\nLine", "[Verse 1]\nLine\n[Chorus]\nHook"],
            alternative: "000",
            project: markers
        )
        let markerResult = try LogicProjectReader().readProject(at: markers)
        try require(markerResult.notes[0].text.contains("[Chorus]"), "More section markers win")

        let lines = root.appendingPathComponent("Lines.logicx", isDirectory: true)
        try writeProjectData(
            ["One\nTwo", "One\nTwo\nThree"],
            alternative: "000",
            project: lines
        )
        let lineResult = try LogicProjectReader().readProject(at: lines)
        try require(lineResult.notes[0].text == "One\nTwo\nThree", "More lyric lines win")

        let length = root.appendingPathComponent("Length.logicx", isDirectory: true)
        try writeProjectData(
            ["A\nB", "A much longer first lyric line\nB"],
            alternative: "000",
            project: length
        )
        let lengthResult = try LogicProjectReader().readProject(at: length)
        try require(lengthResult.notes[0].text.hasPrefix("A much longer"), "Longer text wins the final tie")
    }

    private static func testReaderDecodeFailureFallsBackToDraft() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("Decode-Failure.logicx", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeProjectData(["Readable\nProject notes"], alternative: "000", project: project)

        try require(
            LogicProjectReader.decodeRTF(Data("not an RTF document".utf8)) == nil,
            "Malformed rich text is rejected"
        )
        let reader = LogicProjectReader(decodeRTFDocument: { _ in nil })
        let result = try reader.readProject(at: project)
        try require(
            result.notes.count == 1 && result.notes[0].isDraft && result.notes[0].text.isEmpty,
            "An undecodable rich-text document degrades to an empty draft"
        )
    }

    private static func testReaderDefensiveRTFBranches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cleaned = root.appendingPathComponent("Cleaned.logicx", isDirectory: true)
        try writeProjectData(["", "Repeated\nLyrics", "Repeated\nLyrics"], alternative: "000", project: cleaned)
        let cleanedResult = try LogicProjectReader().readProject(at: cleaned)
        try require(cleanedResult.notes[0].text == "Repeated\nLyrics", "Empty and duplicate RTF values are ignored")

        let short = root.appendingPathComponent("Short.logicx", isDirectory: true)
        try writeRawProjectData(Data([0x01, 0x02]), alternative: "000", project: short)
        let shortResult = try LogicProjectReader().readProject(at: short)
        try require(shortResult.notes[0].isDraft, "A ProjectData buffer shorter than the RTF marker is safe")

        let incomplete = root.appendingPathComponent("Incomplete.logicx", isDirectory: true)
        try writeRawProjectData(Data("{\\rtf1 incomplete".utf8), alternative: "000", project: incomplete)
        let incompleteResult = try LogicProjectReader().readProject(at: incomplete)
        try require(incompleteResult.notes[0].isDraft, "An unterminated RTF group is ignored")

        try require(
            !LogicProjectReader.matches([0x01, 0x02], in: Data([0x01]), at: 0),
            "RTF marker matching checks its upper bound"
        )
        try require(
            LogicProjectReader.advancePastControlSequence(in: Data("\\".utf8), from: 0) == 1,
            "A terminal RTF escape is safe"
        )
        try require(
            LogicProjectReader.advancePastControlSequence(in: Data("\\bin-1 ".utf8), from: 0) == 7,
            "A negative RTF binary count does not skip bytes"
        )
        try require(
            LogicProjectReader.advancePastControlSequence(in: Data("\\bin2 ab".utf8), from: 0) == 8,
            "A positive RTF binary count skips its payload"
        )
    }

    private static func testHistorySearchPolicy() throws {
        let createdAt = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let atLast = historyEntry(
            name: "at last",
            lyrics: "No matching word in these lyrics",
            createdAt: createdAt
        )
        let lyricsOnlyMatch = historyEntry(
            name: "a myth",
            lyrics: "The last train leaves tonight",
            createdAt: createdAt
        )
        let emptyLyrics = historyEntry(
            name: "instrumental draft",
            lyrics: "  \n ",
            createdAt: createdAt
        )
        let entries = [atLast, lyricsOnlyMatch, emptyLyrics]

        try require(
            HistorySearch.filter(entries, query: "", onlyWithoutLyrics: false).map(\.id)
                == entries.map(\.id),
            "An empty history query preserves every entry"
        )
        try require(
            HistorySearch.filter(entries, query: "  LAST  ", onlyWithoutLyrics: false).map(\.id)
                == [atLast.id],
            "History search is trimmed, case-insensitive and title-only"
        )
        try require(
            HistorySearch.filter(entries, query: "missing", onlyWithoutLyrics: false).isEmpty,
            "An unmatched title query returns no history entries"
        )
        try require(
            HistorySearch.filter(entries, query: "", onlyWithoutLyrics: true).map(\.id)
                == [emptyLyrics.id],
            "The no-lyrics filter recognizes whitespace-only Project Notes"
        )
        try require(
            HistorySearch.filter(entries, query: "instrumental", onlyWithoutLyrics: true).map(\.id)
                == [emptyLyrics.id],
            "Title search and the no-lyrics filter compose"
        )
        try require(
            HistorySearch.filter(entries, query: "last", onlyWithoutLyrics: true).isEmpty,
            "The no-lyrics filter excludes a title that has Project Notes"
        )
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

    private static func testSemanticVersionComparison() throws {
        try require(UpdateService.isNewer("2.2.1", than: "2.2.0"), "Patch update comparison")
        try require(UpdateService.isNewer("2.10.0", than: "2.9.9"), "Numeric minor version comparison")
        try require(UpdateService.isNewer("3.0", than: "2.99.99"), "Major version comparison")
        try require(!UpdateService.isNewer("2.2.0", than: "2.2.0"), "Equal version comparison")
        try require(!UpdateService.isNewer("2.1.9", than: "2.2.0"), "Older version comparison")
        try require(!UpdateService.isNewer("3.beta", than: "2.2.0"), "Invalid version rejection")
        try require(!UpdateService.isNewer("3..0", than: "2.2.0"), "Empty version component rejection")
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

    private static func writeRawProjectData(_ data: Data, alternative: String, project: URL) throws {
        let url = project.appendingPathComponent("Alternatives/\(alternative)/ProjectData")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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

    private static func historyEntry(
        name: String,
        lyrics: String,
        createdAt: Date
    ) -> SongHistoryEntry {
        SongHistoryEntry(
            id: UUID(), projectName: name, projectPath: "/tmp/\(name).logicx",
            noteKey: "000#1", alternative: "000", lyrics: lyrics,
            prompt: "", referenceArtist: "", allowsFemaleBackingVocals: false,
            bpm: nil, musicalKey: nil, createdAt: createdAt, updatedAt: createdAt
        )
    }

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestFailure(message) }
        return value
    }

    private static func requireLogicError(
        _ expected: LogicProjectError,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
        } catch let error as LogicProjectError {
            try require(error == expected, "Expected \(expected), received \(error)")
            return
        }
        throw TestFailure("Expected \(expected) to be thrown")
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
