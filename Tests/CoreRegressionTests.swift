import Foundation

@main
enum CoreRegressionTests {
    static func main() throws {
        try testAdjacentSections()
        try testLegacyHistoryMigration()
        try testLogicSourceProtection()
        try testLogicEmptyNoteCreation()
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

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(message) }
    }
}

private struct TestFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
