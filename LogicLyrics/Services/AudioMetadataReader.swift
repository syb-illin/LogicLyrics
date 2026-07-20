import Foundation

struct ExistingAudioMetadata: Sendable {
    var title: String?
    var trackNumber: String?
    var artist: String?
    var album: String?
    var year: Int?
    var genre: String?
    var bpm: Double?
    var lyrics: String?
    var artwork: EmbeddedArtwork?
}

struct AudioMetadataReader: Sendable {
    func read(from url: URL) throws -> ExistingAudioMetadata {
        var metadata: ExistingAudioMetadata
        switch url.pathExtension.lowercased() {
        case "mp3": metadata = try readMP3(url)
        case "wav", "wave": metadata = try readWAV(url)
        default: throw AudioMetadataError.unsupportedFormat
        }
        metadata.artwork = try AudioArtworkReader().read(from: url)
        return metadata
    }

    private func readMP3(_ url: URL) throws -> ExistingAudioMetadata {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 10) ?? Data()
        guard header.count == 10, String(decoding: header[0..<3], as: UTF8.self) == "ID3" else {
            return ExistingAudioMetadata()
        }
        let size = synchsafe(header[6], header[7], header[8], header[9])
        guard size >= 0, size <= 64 * 1_024 * 1_024 else { throw AudioMetadataError.invalidMP3 }
        let body = try handle.read(upToCount: size) ?? Data()
        guard body.count == size else { throw AudioMetadataError.invalidMP3 }
        return parseID3(body: body, version: header[3], flags: header[5])
    }

    private func readWAV(_ url: URL) throws -> ExistingAudioMetadata {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 12) ?? Data()
        guard header.count == 12,
              String(decoding: header[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: header[8..<12], as: UTF8.self) == "WAVE" else {
            throw AudioMetadataError.invalidWAV
        }
        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 12)
        var result = ExistingAudioMetadata()
        while try handle.offset() + 8 <= fileSize {
            try Task<Never, Never>.checkCancellation()
            let chunkHeader = try handle.read(upToCount: 8) ?? Data()
            guard chunkHeader.count == 8 else { break }
            let identifier = String(decoding: chunkHeader[0..<4], as: UTF8.self)
            let size = Int(le32(chunkHeader[4..<8]))
            let payloadOffset = try handle.offset()
            let paddedEnd = payloadOffset + UInt64(size + size % 2)
            guard paddedEnd <= fileSize else { throw AudioMetadataError.invalidWAV }

            if identifier == "LIST", size >= 4 {
                let payload = try handle.read(upToCount: min(size, 8 * 1_024 * 1_024)) ?? Data()
                if payload.count == size, String(decoding: payload.prefix(4), as: UTF8.self) == "INFO" {
                    applyINFO(Data(payload.dropFirst(4)), to: &result)
                }
            } else if ["id3 ", "ID3 "].contains(identifier), size >= 10, size <= 64 * 1_024 * 1_024 {
                let tag = try handle.read(upToCount: size) ?? Data()
                if tag.count >= 10, String(decoding: tag.prefix(3), as: UTF8.self) == "ID3" {
                    let id3Size = min(synchsafe(tag[6], tag[7], tag[8], tag[9]), tag.count - 10)
                    let parsed = parseID3(body: Data(tag[10..<(10 + id3Size)]), version: tag[3], flags: tag[5])
                    merge(parsed, into: &result)
                }
            }
            try handle.seek(toOffset: paddedEnd)
        }
        return result
    }

    private func parseID3(body: Data, version: UInt8, flags: UInt8) -> ExistingAudioMetadata {
        guard version == 3 || version == 4, flags & 0x80 == 0 else { return ExistingAudioMetadata() }
        var offset = 0
        if flags & 0x40 != 0, body.count >= 4 {
            let extendedSize = version == 4
                ? synchsafe(body[0], body[1], body[2], body[3])
                : Int(be32(body[0..<4])) + 4
            offset = min(max(0, extendedSize), body.count)
        }
        var result = ExistingAudioMetadata()
        while offset + 10 <= body.count {
            let id = String(decoding: body[offset..<(offset + 4)], as: UTF8.self)
            guard id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { break }
            let size = version == 4
                ? synchsafe(body[offset + 4], body[offset + 5], body[offset + 6], body[offset + 7])
                : Int(be32(body[(offset + 4)..<(offset + 8)]))
            let start = offset + 10, end = start + size
            guard size >= 0, end <= body.count else { break }
            let payload = Data(body[start..<end])
            switch id {
            case "TIT2": result.title = decodeText(payload)
            case "TRCK": result.trackNumber = decodeText(payload)
            case "TPE1": result.artist = decodeText(payload)
            case "TALB": result.album = decodeText(payload)
            case "TCON": result.genre = decodeText(payload)
            case "TBPM": result.bpm = decodeText(payload).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            case "TYER", "TDRC": result.year = decodeText(payload).flatMap { Int($0.prefix(4)) }
            case "USLT": result.lyrics = decodeLyrics(payload)
            default: break
            }
            offset = end
        }
        return result
    }

    private func applyINFO(_ data: Data, to metadata: inout ExistingAudioMetadata) {
        var offset = 0
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            let size = Int(le32(data[(offset + 4)..<(offset + 8)]))
            let start = offset + 8, end = start + size
            guard size >= 0, end <= data.count else { break }
            let raw = Data(data[start..<end]).prefix { $0 != 0 }
            let value = String(data: Data(raw), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                switch id {
                case "INAM": metadata.title = value
                case "ITRK": metadata.trackNumber = value
                case "IART": metadata.artist = value
                case "IPRD": metadata.album = value
                case "ICRD": metadata.year = Int(value.prefix(4))
                case "IGNR": metadata.genre = value
                case "IBPM": metadata.bpm = Double(value.replacingOccurrences(of: ",", with: "."))
                default: break
                }
            }
            offset = end + size % 2
        }
    }

    private func merge(_ source: ExistingAudioMetadata, into destination: inout ExistingAudioMetadata) {
        destination.title = source.title ?? destination.title
        destination.trackNumber = source.trackNumber ?? destination.trackNumber
        destination.artist = source.artist ?? destination.artist
        destination.album = source.album ?? destination.album
        destination.year = source.year ?? destination.year
        destination.genre = source.genre ?? destination.genre
        destination.bpm = source.bpm ?? destination.bpm
        destination.lyrics = source.lyrics ?? destination.lyrics
    }

    private func decodeText(_ payload: Data) -> String? {
        guard let encoding = payload.first else { return nil }
        return decode(Data(payload.dropFirst()), encoding: encoding)
    }

    private func decodeLyrics(_ payload: Data) -> String? {
        guard payload.count >= 5 else { return nil }
        let encoding = payload[0]
        var cursor = 4
        if encoding == 0 || encoding == 3 {
            guard let end = payload[cursor...].firstIndex(of: 0) else { return nil }
            cursor = end + 1
        } else {
            while cursor + 1 < payload.count {
                if payload[cursor] == 0, payload[cursor + 1] == 0 { cursor += 2; break }
                cursor += 2
            }
        }
        guard cursor <= payload.count else { return nil }
        return decode(Data(payload[cursor...]), encoding: encoding)
    }

    private func decode(_ data: Data, encoding: UInt8) -> String? {
        let value: String?
        switch encoding {
        case 0: value = String(data: data, encoding: .isoLatin1)
        case 1: value = String(data: data, encoding: .utf16)
        case 2: value = String(data: data, encoding: .utf16BigEndian)
        case 3: value = String(data: data, encoding: .utf8)
        default: value = nil
        }
        return value?.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
    }

    private func synchsafe(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        (Int(a & 127) << 21) | (Int(b & 127) << 14) | (Int(c & 127) << 7) | Int(d & 127)
    }
    private func le32(_ data: Data.SubSequence) -> UInt32 {
        data.enumerated().reduce(0) { $0 | (UInt32($1.element) << UInt32($1.offset * 8)) }
    }
    private func be32(_ data: Data.SubSequence) -> UInt32 { data.reduce(0) { ($0 << 8) | UInt32($1) } }
}
