import AppKit
import Foundation

enum LogicProjectWriteError: LocalizedError {
    case sourceEqualsDestination
    case noteNotFound
    case emptyLyrics
    case emptyNoteContainerNotFound
    case encodedTextTooLarge(available: Int, required: Int)
    case validationFailed

    var errorDescription: String? {
        switch self {
        case .sourceEqualsDestination:
            "La destination correspond au projet Logic original. Choisis obligatoirement un autre nom ou un autre dossier."
        case .noteNotFound:
            "Le bloc de Notes correspondant n’a pas été retrouvé dans ProjectData."
        case .emptyLyrics:
            "Écris les paroles avant de créer la copie Logic."
        case .emptyNoteContainerNotFound:
            "Ce projet ne contient pas la structure de Notes vide reconnue. La copie n’a pas été créée afin d’éviter toute corruption."
        case .encodedTextTooLarge(let available, let required):
            "Les paroles corrigées nécessitent \(required) octets, mais le bloc Logic n’en réserve que \(available). La copie n’a pas été créée."
        case .validationFailed:
            "La copie a été annulée car la relecture des paroles modifiées a échoué."
        }
    }
}

struct LogicProjectWriter: Sendable {
    func createEditedCopy(
        source: URL,
        destination: URL,
        alternative: String,
        originalText: String,
        editedText: String
    ) throws {
        try Task<Never, Never>.checkCancellation()
        guard !sameFile(source, destination) else {
            throw LogicProjectWriteError.sourceEqualsDestination
        }
        guard !clean(editedText).isEmpty else { throw LogicProjectWriteError.emptyLyrics }

        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-LogicLyrics.logicx", isDirectory: true)
        var committed = false
        defer {
            if !committed { try? FileManager.default.removeItem(at: temporary) }
        }

        try FileManager.default.copyItem(at: source, to: temporary)
        try Task<Never, Never>.checkCancellation()

        let projectDataURL = temporary
            .appendingPathComponent("Alternatives", isDirectory: true)
            .appendingPathComponent(alternative, isDirectory: true)
            .appendingPathComponent("ProjectData")
        var projectData = try Data(contentsOf: projectDataURL, options: [.mappedIfSafe])

        let attributed = NSAttributedString(string: editedText)
        let replacement = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        if let targetRange = try findRTFRange(in: projectData, matching: originalText) {
            try replaceRTF(in: &projectData, range: targetRange, with: replacement)
        } else if clean(originalText).isEmpty {
            try appendRTFToEmptyNotesRecord(replacement, in: &projectData)
        } else {
            throw LogicProjectWriteError.noteNotFound
        }
        try Task<Never, Never>.checkCancellation()
        try projectData.write(to: projectDataURL, options: .atomic)

        let result = try LogicProjectReader().readProject(at: temporary)
        let expected = clean(editedText)
        guard result.notes.contains(where: { $0.alternative == alternative && clean($0.text) == expected }) else {
            throw LogicProjectWriteError.validationFailed
        }
        try Task<Never, Never>.checkCancellation()

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        committed = true
    }

    private func replaceRTF(in data: inout Data, range: Range<Int>, with replacement: Data) throws {
        if replacement.count <= range.count {
            data.replaceSubrange(range, with: padRTF(replacement, to: range.count))
            return
        }
        guard let recordStart = trailingNotesRecordStart(in: data, payloadRange: range) else {
            throw LogicProjectWriteError.encodedTextTooLarge(
                available: range.count,
                required: replacement.count
            )
        }
        data.replaceSubrange(range, with: replacement)
        try updateTrailingNotesLength(in: &data, recordStart: recordStart)
    }

    private func appendRTFToEmptyNotesRecord(_ rtf: Data, in data: inout Data) throws {
        let emptyRange = data.endIndex..<data.endIndex
        guard let recordStart = trailingNotesRecordStart(in: data, payloadRange: emptyRange) else {
            throw LogicProjectWriteError.emptyNoteContainerNotFound
        }
        data.append(rtf)
        try updateTrailingNotesLength(in: &data, recordStart: recordStart)
    }

    /// Logic's Project Notes payload is the last member of a record whose
    /// fixed header is 98 bytes. Two little-endian fields contain the exact
    /// total record length. We only resize when every observed invariant is
    /// present, so unrelated binary data can never be treated as a note slot.
    private func trailingNotesRecordStart(in data: Data, payloadRange: Range<Int>) -> Int? {
        let headerSize = 98
        guard payloadRange.upperBound == data.endIndex,
              payloadRange.lowerBound >= headerSize else { return nil }
        let start = payloadRange.lowerBound - headerSize
        let totalSize = data.count - start
        guard totalSize <= Int(UInt32.max),
              readLittleEndianUInt32(data, at: start) == UInt32(totalSize),
              readLittleEndianUInt32(data, at: start + 16) == UInt32(headerSize),
              readLittleEndianUInt32(data, at: start + 20) == UInt32(totalSize),
              data[start + 24] == 0x13,
              data[start + 25] == 0x00,
              data[start + 26] == 0xFF,
              data[start + 27] == 0x00,
              data[(start + 36)..<(start + headerSize)].allSatisfy({ $0 == 0 }) else {
            return nil
        }
        return start
    }

    private func updateTrailingNotesLength(in data: inout Data, recordStart: Int) throws {
        let size = data.count - recordStart
        guard size <= Int(UInt32.max) else {
            throw LogicProjectWriteError.encodedTextTooLarge(available: Int(UInt32.max), required: size)
        }
        let bytes = withUnsafeBytes(of: UInt32(size).littleEndian) { Data($0) }
        data.replaceSubrange(recordStart..<(recordStart + 4), with: bytes)
        data.replaceSubrange((recordStart + 20)..<(recordStart + 24), with: bytes)
    }

    private func readLittleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return UInt32.max }
        return data[offset..<(offset + 4)].enumerated().reduce(0) {
            $0 | (UInt32($1.element) << UInt32($1.offset * 8))
        }
    }

    private func sameFile(_ source: URL, _ destination: URL) -> Bool {
        let sourceURL = source.standardizedFileURL.resolvingSymlinksInPath()
        let destinationURL = destination.standardizedFileURL.resolvingSymlinksInPath()
        if sourceURL == destinationURL { return true }
        guard FileManager.default.fileExists(atPath: destinationURL.path),
              let sourceID = try? sourceURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let destinationID = try? destinationURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else {
            return false
        }
        return String(describing: sourceID) == String(describing: destinationID)
    }

    private func findRTFRange(in data: Data, matching text: String) throws -> Range<Int>? {
        let marker = Array("{\\rtf1".utf8)
        guard data.count >= marker.count else { return nil }
        var cursor = 0
        while cursor <= data.count - marker.count {
            if cursor % 65_536 == 0 { try Task<Never, Never>.checkCancellation() }
            guard data[cursor..<(cursor + marker.count)].elementsEqual(marker) else { cursor += 1; continue }
            let start = cursor
            var index = cursor, depth = 0
            while index < data.count {
                switch data[index] {
                case 0x7B: depth += 1; index += 1
                case 0x7D:
                    depth -= 1; index += 1
                    if depth == 0 {
                        let range = start..<index
                        if decode(data.subdata(in: range)).map(clean) == clean(text) {
                            if clean(text).isEmpty {
                                if trailingNotesRecordStart(in: data, payloadRange: range) != nil { return range }
                            } else {
                                return range
                            }
                        }
                        cursor = index
                        break
                    }
                case 0x5C: index = advancePastControlSequence(data, from: index)
                default: index += 1
                }
                if depth == 0 { break }
            }
            if depth != 0 { cursor = start + marker.count }
        }
        return nil
    }

    private func advancePastControlSequence(_ bytes: Data, from slash: Int) -> Int {
        var index = slash + 1
        guard index < bytes.count else { return index }
        guard isLetter(bytes[index]) else { return min(index + 1, bytes.count) }
        let wordStart = index
        while index < bytes.count, isLetter(bytes[index]) { index += 1 }
        let word = String(decoding: bytes[wordStart..<index], as: UTF8.self)
        if index < bytes.count, bytes[index] == 0x2D { index += 1 }
        let numberStart = index
        while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        let count = Int(String(decoding: bytes[numberStart..<index], as: UTF8.self))
        if index < bytes.count, bytes[index] == 0x20 { index += 1 }
        return word == "bin" ? min(index + (count ?? 0), bytes.count) : index
    }

    private func padRTF(_ rtf: Data, to count: Int) -> Data {
        guard rtf.count < count, rtf.last == 0x7D else { return rtf }
        var result = Data(rtf.dropLast())
        result.append(contentsOf: repeatElement(UInt8(0x20), count: count - rtf.count))
        result.append(0x7D)
        return result
    }

    private func decode(_ data: Data) -> String? {
        guard let value = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }
        return value.string
    }

    private func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
}
