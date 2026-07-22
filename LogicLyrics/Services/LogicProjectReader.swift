import AppKit
import Foundation

enum LogicProjectError: LocalizedError {
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

struct LogicProjectReader: Sendable {
    private static let signature = Data("{\\rtf1".utf8)

    private struct NoteCandidate {
        let index: Int
        let text: String

        var nonEmptyLineCount: Int {
            text.split(whereSeparator: \.isNewline).count
        }

        var sectionMarkerCount: Int {
            text.components(separatedBy: "[").dropFirst().reduce(into: 0) { count, component in
                let label = component.prefix { $0 != "]" }.lowercased()
                if ["verse", "chorus", "pre-chorus", "bridge", "intro", "outro", "hook", "refrain"]
                    .contains(where: { label.hasPrefix($0) }) {
                    count += 1
                }
            }
        }

        var isLikelyProjectNote: Bool {
            nonEmptyLineCount > 1 || sectionMarkerCount > 0
        }
    }

    struct Result: Sendable {
        let notes: [ExtractedNote]
        let bpm: Double?
        let musicalKey: String?
    }

    func readProject(at projectURL: URL) throws -> Result {
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

        let alternativesURL = projectURL.appendingPathComponent("Alternatives", isDirectory: true)
        guard let alternatives = try? FileManager.default.contentsOfDirectory(
            at: alternativesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw LogicProjectError.alternativesMissing
        }

        let projectDataURLs = alternatives
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.appendingPathComponent("ProjectData") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.deletingLastPathComponent().lastPathComponent < $1.deletingLastPathComponent().lastPathComponent }

        guard !projectDataURLs.isEmpty else { throw LogicProjectError.noProjectData }

        // Logic stores many unrelated rich-text values in ProjectData (loop names,
        // region annotations, and Project Notes). Reading every RTF made a loop name
        // appear as the selected lyrics. The active alternative is the project state
        // visible in Logic, and its richest multi-line RTF is the Project Notes value.
        let activeProjectDataURL = preferredProjectDataURL(
            among: projectDataURLs,
            projectURL: projectURL
        )
        let alternative = activeProjectDataURL.deletingLastPathComponent().lastPathComponent
        let data = try Data(contentsOf: activeProjectDataURL, options: [.mappedIfSafe])
        let candidates = try noteCandidates(in: data)

        let notes: [ExtractedNote]
        if let candidate = candidates
            .filter(\.isLikelyProjectNote)
            .max(by: { isLowerQuality($0, than: $1) }) {
            notes = [ExtractedNote(
                alternative: alternative,
                index: candidate.index,
                text: candidate.text
            )]
        } else {
            notes = [ExtractedNote(alternative: alternative, index: 0, text: "", isDraft: true)]
        }

        let metadata = readMetadata(beside: activeProjectDataURL)
        return Result(notes: notes, bpm: metadata.bpm, musicalKey: metadata.musicalKey)
    }

    private func preferredProjectDataURL(among urls: [URL], projectURL: URL) -> URL {
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

    private func noteCandidates(in data: Data) throws -> [NoteCandidate] {
        var candidates: [NoteCandidate] = []
        var seenTexts = Set<String>()
        var nonEmptyIndex = 0
        for rtf in try extractRTFDocuments(from: data) {
            guard let text = decodeRTF(rtf) else { continue }
            let cleaned = clean(text)
            guard !cleaned.isEmpty else { continue }
            guard seenTexts.insert(cleaned).inserted else { continue }
            candidates.append(NoteCandidate(index: nonEmptyIndex, text: cleaned))
            nonEmptyIndex += 1
        }
        return candidates
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

    /// Extracts complete RTF groups embedded in Logic's binary ProjectData.
    /// Handles escaped braces and RTF `\\binN` payloads so binary bytes cannot
    /// prematurely terminate the group.
    private func extractRTFDocuments(from data: Data) throws -> [Data] {
        let marker = [UInt8](Self.signature)
        guard data.count >= marker.count else { return [] }

        var results: [Data] = []
        var cursor = 0

        while cursor <= data.count - marker.count {
            if cursor % 65_536 == 0 { try Task<Never, Never>.checkCancellation() }
            guard matches(marker, in: data, at: cursor) else {
                cursor += 1
                continue
            }

            let start = cursor
            var index = cursor
            var depth = 0

            while index < data.count {
                switch data[index] {
                case 0x7B: // {
                    depth += 1
                    index += 1
                case 0x7D: // }
                    depth -= 1
                    index += 1
                    if depth == 0 {
                        results.append(data.subdata(in: start..<index))
                        cursor = index
                        break
                    }
                case 0x5C: // backslash
                    index = advancePastControlSequence(in: data, from: index)
                default:
                    index += 1
                }

                if depth == 0 { break }
            }

            if depth != 0 { cursor = start + marker.count }
        }
        return results
    }

    private func matches(_ marker: [UInt8], in data: Data, at index: Int) -> Bool {
        guard index + marker.count <= data.count else { return false }
        return data[index..<(index + marker.count)].elementsEqual(marker)
    }

    private func advancePastControlSequence(in bytes: Data, from slash: Int) -> Int {
        var index = slash + 1
        guard index < bytes.count else { return index }

        // Escaped character: \\{, \\}, \\\\, \\~ etc.
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

    private func asciiLetter(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
    }

    private func asciiDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }

    private func decodeRTF(_ data: Data) -> String? {
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
