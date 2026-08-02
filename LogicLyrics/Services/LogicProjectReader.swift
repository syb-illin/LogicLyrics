import AppKit
import Foundation

enum LogicProjectError: LocalizedError, Equatable {
    case notLogicProject
    case alternativesMissing
    case noProjectData
    case unreadableProject

    var errorDescription: String? {
        switch self {
        case .notLogicProject: L10n.text("Drop a Logic Pro project in .logicx format.")
        case .alternativesMissing: L10n.text("This project does not contain an Alternatives folder.")
        case .noProjectData: L10n.text("No ProjectData file was found.")
        case .unreadableProject: L10n.text("The project cannot be read.")
        }
    }
}

struct ExtractionDiagnostics: Codable, Equatable, Hashable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case selected
        case noEmbeddedRichText
        case richTextCouldNotBeDecoded
        case noLikelyProjectNotes
    }

    let outcome: Outcome
    let embeddedRichTextCount: Int
    let decodedCandidateCount: Int
    let likelyProjectNotesCount: Int
    let selectedCandidateIndex: Int?

    var localizedSummary: String {
        switch outcome {
        case .selected:
            L10n.format(
                "Selected Project Notes from %d decoded rich-text candidates.",
                decodedCandidateCount
            )
        case .noEmbeddedRichText:
            L10n.text("No embedded rich-text document was found in this alternative.")
        case .richTextCouldNotBeDecoded:
            L10n.format(
                "%d embedded rich-text documents were found, but none could be decoded.",
                embeddedRichTextCount
            )
        case .noLikelyProjectNotes:
            L10n.format(
                "%d rich-text candidates were decoded, but none looked like multi-line Project Notes.",
                decodedCandidateCount
            )
        }
    }
}

struct LogicProjectReader: Sendable {
    private static let signature = Data("{\\rtf1".utf8)
    private let decodeRTFDocument: @Sendable (Data) -> String?

    init(
        decodeRTFDocument: @escaping @Sendable (Data) -> String? = {
            LogicProjectReader.decodeRTF($0)
        }
    ) {
        self.decodeRTFDocument = decodeRTFDocument
    }

    private struct NoteCandidate {
        let index: Int
        let text: String

        var nonEmptyLineCount: Int { text.split(whereSeparator: \.isNewline).count }
        var sectionMarkerCount: Int { LyricSectionParser.parse(text).count }
        var isLikelyProjectNote: Bool { nonEmptyLineCount > 1 || sectionMarkerCount > 0 }
    }

    struct Result: Sendable {
        let notes: [ExtractedNote]
        let bpm: Double?
        let musicalKey: String?
        let availableAlternatives: [String]
        let selectedAlternative: String
        let diagnostics: ExtractionDiagnostics
        let sourceStateToken: String

        init(
            notes: [ExtractedNote],
            bpm: Double?,
            musicalKey: String?,
            availableAlternatives: [String]? = nil,
            selectedAlternative: String? = nil,
            diagnostics: ExtractionDiagnostics? = nil,
            sourceStateToken: String = "test-state"
        ) {
            self.notes = notes
            self.bpm = bpm
            self.musicalKey = musicalKey
            let inferredAlternative = selectedAlternative ?? notes.first?.alternative ?? ""
            self.availableAlternatives = availableAlternatives ?? [inferredAlternative].filter { !$0.isEmpty }
            self.selectedAlternative = inferredAlternative
            self.diagnostics = diagnostics ?? ExtractionDiagnostics(
                outcome: notes.first?.text.isEmpty == false ? .selected : .noLikelyProjectNotes,
                embeddedRichTextCount: notes.first?.text.isEmpty == false ? 1 : 0,
                decodedCandidateCount: notes.first?.text.isEmpty == false ? 1 : 0,
                likelyProjectNotesCount: notes.first?.text.isEmpty == false ? 1 : 0,
                selectedCandidateIndex: notes.first?.index
            )
            self.sourceStateToken = sourceStateToken
        }
    }

    func readProject(at projectURL: URL) throws -> Result {
        try readProject(at: projectURL, preferredAlternative: nil)
    }

    func readProject(at projectURL: URL, preferredAlternative: String?) throws -> Result {
        try withProjectAccess(projectURL) {
            let projectDataURLs = try discoverProjectData(in: projectURL)
            let selectedURL = preferredProjectDataURL(
                among: projectDataURLs,
                projectURL: projectURL,
                preferredAlternative: preferredAlternative
            )
            let alternative = selectedURL.deletingLastPathComponent().lastPathComponent
            let data = try Data(contentsOf: selectedURL, options: [.mappedIfSafe])
            let documents = try extractRTFDocuments(from: data)
            let candidates = noteCandidates(in: documents)
            let plausible = candidates.filter(\.isLikelyProjectNote)
            let selected = plausible.max(by: { isLowerQuality($0, than: $1) })
            let diagnostics = ExtractionDiagnostics(
                outcome: diagnosticOutcome(documents: documents, candidates: candidates, selected: selected),
                embeddedRichTextCount: documents.count,
                decodedCandidateCount: candidates.count,
                likelyProjectNotesCount: plausible.count,
                selectedCandidateIndex: selected?.index
            )
            let note = selected.map {
                ExtractedNote(alternative: alternative, index: $0.index, text: $0.text)
            } ?? ExtractedNote(alternative: alternative, index: 0, text: "", isDraft: true)
            let metadata = readMetadata(beside: selectedURL)
            return Result(
                notes: [note],
                bpm: metadata.bpm,
                musicalKey: metadata.musicalKey,
                availableAlternatives: projectDataURLs.map {
                    $0.deletingLastPathComponent().lastPathComponent
                },
                selectedAlternative: alternative,
                diagnostics: diagnostics,
                sourceStateToken: try stateToken(
                    projectURL: projectURL,
                    selectedProjectDataURL: selectedURL
                )
            )
        }
    }

    /// Cheap state check used when the app becomes active. It reads only file
    /// metadata and never scans the binary ProjectData contents.
    func projectStateToken(at projectURL: URL, preferredAlternative: String?) throws -> String {
        try withProjectAccess(projectURL) {
            let projectDataURLs = try discoverProjectData(in: projectURL)
            let selectedURL = preferredProjectDataURL(
                among: projectDataURLs,
                projectURL: projectURL,
                preferredAlternative: preferredAlternative
            )
            return try stateToken(projectURL: projectURL, selectedProjectDataURL: selectedURL)
        }
    }

    private func withProjectAccess<T>(_ projectURL: URL, operation: () throws -> T) throws -> T {
        guard projectURL.pathExtension.lowercased() == "logicx" else {
            throw LogicProjectError.notLogicProject
        }
        let didAccess = projectURL.startAccessingSecurityScopedResource()
        defer { if didAccess { projectURL.stopAccessingSecurityScopedResource() } }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LogicProjectError.unreadableProject
        }
        return try operation()
    }

    private func discoverProjectData(in projectURL: URL) throws -> [URL] {
        let alternativesURL = projectURL.appendingPathComponent("Alternatives", isDirectory: true)
        guard let alternatives = try? FileManager.default.contentsOfDirectory(
            at: alternativesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw LogicProjectError.alternativesMissing
        }
        let urls = alternatives
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.appendingPathComponent("ProjectData") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted {
                $0.deletingLastPathComponent().lastPathComponent
                    < $1.deletingLastPathComponent().lastPathComponent
            }
        guard !urls.isEmpty else { throw LogicProjectError.noProjectData }
        return urls
    }

    private func preferredProjectDataURL(
        among urls: [URL],
        projectURL: URL,
        preferredAlternative: String?
    ) -> URL {
        if let preferredAlternative,
           let preferred = urls.first(where: {
               $0.deletingLastPathComponent().lastPathComponent == preferredAlternative
           }) {
            return preferred
        }
        if let activeAlternative = activeAlternativeName(in: projectURL),
           let activeURL = urls.first(where: {
               $0.deletingLastPathComponent().lastPathComponent == activeAlternative
           }) {
            return activeURL
        }
        return urls[urls.count - 1]
    }

    private func activeAlternativeName(in projectURL: URL) -> String? {
        let informationURL = projectURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("ProjectInformation.plist")
        guard let data = try? Data(contentsOf: informationURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: Any] else { return nil }

        if let value = values["ActiveVariant"] as? NSNumber {
            return String(format: "%03d", value.intValue)
        }
        if let value = values["ActiveVariant"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Int(trimmed) { return String(format: "%03d", number) }
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func noteCandidates(in documents: [Data]) -> [NoteCandidate] {
        var candidates: [NoteCandidate] = []
        var seenTexts = Set<String>()
        var nonEmptyIndex = 0
        for rtf in documents {
            guard let text = decodeRTFDocument(rtf) else { continue }
            let cleaned = clean(text)
            guard !cleaned.isEmpty, seenTexts.insert(cleaned).inserted else { continue }
            candidates.append(NoteCandidate(index: nonEmptyIndex, text: cleaned))
            nonEmptyIndex += 1
        }
        return candidates
    }

    private func diagnosticOutcome(
        documents: [Data],
        candidates: [NoteCandidate],
        selected: NoteCandidate?
    ) -> ExtractionDiagnostics.Outcome {
        if selected != nil { return .selected }
        if documents.isEmpty { return .noEmbeddedRichText }
        if candidates.isEmpty { return .richTextCouldNotBeDecoded }
        return .noLikelyProjectNotes
    }

    private func isLowerQuality(_ candidate: NoteCandidate, than other: NoteCandidate) -> Bool {
        if candidate.sectionMarkerCount != other.sectionMarkerCount {
            return candidate.sectionMarkerCount < other.sectionMarkerCount
        }
        if candidate.nonEmptyLineCount != other.nonEmptyLineCount {
            return candidate.nonEmptyLineCount < other.nonEmptyLineCount
        }
        return candidate.text.count < other.text.count
    }

    private func readMetadata(beside projectDataURL: URL) -> (bpm: Double?, musicalKey: String?) {
        let url = projectDataURL.deletingLastPathComponent().appendingPathComponent("MetaData.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: Any] else { return (nil, nil) }

        let rawBPM = (values["BeatsPerMinute"] as? NSNumber)?.doubleValue
        let bpm = rawBPM.flatMap { (20...400).contains($0) ? $0 : nil }
        let tonic = (values["SongKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = (values["SongGenderKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyParts = [tonic, mode].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return (bpm, keyParts.isEmpty ? nil : keyParts.joined(separator: " "))
    }

    private func stateToken(projectURL: URL, selectedProjectDataURL: URL) throws -> String {
        let metadataURL = selectedProjectDataURL.deletingLastPathComponent()
            .appendingPathComponent("MetaData.plist")
        let informationURL = projectURL.appendingPathComponent("Resources/ProjectInformation.plist")
        return try [selectedProjectDataURL, metadataURL, informationURL].map { url in
            guard FileManager.default.fileExists(atPath: url.path) else {
                return "\(url.lastPathComponent):missing"
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            return "\(url.lastPathComponent):\(size):\(modified)"
        }.joined(separator: "|")
    }

    /// Extracts complete RTF groups embedded in Logic's binary ProjectData.
    /// Handles escaped braces and RTF `\\binN` payloads.
    private func extractRTFDocuments(from data: Data) throws -> [Data] {
        let marker = [UInt8](Self.signature)
        guard data.count >= marker.count else { return [] }
        var results: [Data] = []
        var cursor = 0

        while cursor <= data.count - marker.count {
            if cursor % 65_536 == 0 { try Task<Never, Never>.checkCancellation() }
            guard Self.matches(marker, in: data, at: cursor) else {
                cursor += 1
                continue
            }
            let start = cursor
            var index = cursor
            var depth = 0
            while index < data.count {
                switch data[index] {
                case 0x7B:
                    depth += 1
                    index += 1
                case 0x7D:
                    depth -= 1
                    index += 1
                    if depth == 0 {
                        results.append(data.subdata(in: start..<index))
                        cursor = index
                        break
                    }
                case 0x5C:
                    index = Self.advancePastControlSequence(in: data, from: index)
                default:
                    index += 1
                }
                if depth == 0 { break }
            }
            if depth != 0 { cursor = start + marker.count }
        }
        return results
    }

    static func matches(_ marker: [UInt8], in data: Data, at index: Int) -> Bool {
        guard index + marker.count <= data.count else { return false }
        return data[index..<(index + marker.count)].elementsEqual(marker)
    }

    static func advancePastControlSequence(in bytes: Data, from slash: Int) -> Int {
        var index = slash + 1
        guard index < bytes.count else { return index }
        guard asciiLetter(bytes[index]) else { return min(index + 1, bytes.count) }
        let wordStart = index
        while index < bytes.count, asciiLetter(bytes[index]) { index += 1 }
        let word = String(decoding: bytes[wordStart..<index], as: UTF8.self)
        var sign = 1
        if index < bytes.count, bytes[index] == 0x2D { sign = -1; index += 1 }
        let numberStart = index
        while index < bytes.count, asciiDigit(bytes[index]) { index += 1 }
        let number = Int(String(decoding: bytes[numberStart..<index], as: UTF8.self)).map { $0 * sign }
        if index < bytes.count, bytes[index] == 0x20 { index += 1 }
        if word == "bin", let count = number, count > 0 {
            return min(index + count, bytes.count)
        }
        return index
    }

    private static func asciiLetter(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
    }

    private static func asciiDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }

    static func decodeRTF(_ data: Data) -> String? {
        guard let value = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }
        return value.string
    }

    private func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
