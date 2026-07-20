import AppKit
import Foundation

enum LogicProjectError: LocalizedError {
    case notLogicProject
    case alternativesMissing
    case noProjectData
    case unreadableProject

    var errorDescription: String? {
        switch self {
        case .notLogicProject: "Dépose un projet Logic Pro au format .logicx."
        case .alternativesMissing: "Le dossier Alternatives est absent de ce projet."
        case .noProjectData: "Aucun fichier ProjectData n’a été trouvé."
        case .unreadableProject: "Le projet ne peut pas être lu."
        }
    }
}

struct LogicProjectReader: Sendable {
    private static let signature = Data("{\\rtf1".utf8)

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

        var notes: [ExtractedNote] = []
        var firstEmptyNoteAlternative: String?
        for dataURL in projectDataURLs {
            try Task<Never, Never>.checkCancellation()
            let data = try Data(contentsOf: dataURL, options: [.mappedIfSafe])
            let alternative = dataURL.deletingLastPathComponent().lastPathComponent
            var seenTexts = Set<String>()
            var noteIndex = 0
            for rtf in try extractRTFDocuments(from: data) {
                guard let text = decodeRTF(rtf) else { continue }
                let cleaned = clean(text)
                guard !cleaned.isEmpty else {
                    if firstEmptyNoteAlternative == nil { firstEmptyNoteAlternative = alternative }
                    continue
                }
                guard seenTexts.insert(cleaned).inserted else { continue }
                notes.append(ExtractedNote(
                    alternative: alternative,
                    index: noteIndex,
                    text: cleaned
                ))
                noteIndex += 1
            }
        }

        if notes.isEmpty {
            let alternative = firstEmptyNoteAlternative
                ?? projectDataURLs[0].deletingLastPathComponent().lastPathComponent
            notes = [ExtractedNote(alternative: alternative, index: 0, text: "", isDraft: true)]
        }
        let metadata = readMetadata(beside: projectDataURLs[0])
        return Result(notes: notes, bpm: metadata.bpm, musicalKey: metadata.musicalKey)
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
