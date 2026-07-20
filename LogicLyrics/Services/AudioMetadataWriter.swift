import Foundation

struct AudioTechnicalInfo: Sendable {
    let format: String
    let codec: String
    let sampleRate: Int?
    let bitDepth: Int?
    let bitrateKbps: Int?
    let channels: Int?
    let duration: TimeInterval?
    let fileSize: Int64
}

struct EmbeddedArtwork: Sendable {
    let data: Data
    let mimeType: String
}

struct AudioArtworkReader: Sendable {
    func read(from url: URL) throws -> EmbeddedArtwork? {
        switch url.pathExtension.lowercased() {
        case "mp3":
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let header = try handle.read(upToCount: 10) ?? Data()
            guard header.count == 10, String(decoding: header[0..<3], as: UTF8.self) == "ID3" else { return nil }
            let size = synchsafe(header[6], header[7], header[8], header[9])
            guard size > 0, size <= 50_000_000 else { return nil }
            let body = try handle.read(upToCount: size) ?? Data()
            return artwork(inID3Body: body, version: header[3])
        case "wav", "wave":
            return try readWAV(url)
        default: return nil
        }
    }

    private func readWAV(_ url: URL) throws -> EmbeddedArtwork? {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let header = try handle.read(upToCount: 12) ?? Data()
        guard header.count == 12, String(decoding: header[0..<4], as: UTF8.self) == "RIFF" else { return nil }
        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 12)
        while try handle.offset() + 8 <= fileSize {
            try Task<Never, Never>.checkCancellation()
            let chunk = try handle.read(upToCount: 8) ?? Data(); if chunk.isEmpty { return nil }
            guard chunk.count == 8 else { return nil }
            let id = String(decoding: chunk[0..<4], as: UTF8.self)
            let size = Int(le32(chunk[4..<8])); let payloadOffset = try handle.offset()
            let paddedEnd = payloadOffset + UInt64(size + size % 2)
            guard paddedEnd <= fileSize else { return nil }
            if ["id3 ", "ID3 "].contains(id), size >= 10, size <= 50_000_000 {
                let tag = try handle.read(upToCount: size) ?? Data()
                guard tag.count >= 10, String(decoding: tag[0..<3], as: UTF8.self) == "ID3" else { return nil }
                return artwork(inID3Body: Data(tag.dropFirst(10)), version: tag[3])
            }
            try handle.seek(toOffset: paddedEnd)
        }
        return nil
    }

    private func artwork(inID3Body body: Data, version: UInt8) -> EmbeddedArtwork? {
        var offset = 0
        while offset + 10 <= body.count {
            let id = String(decoding: body[offset..<(offset + 4)], as: UTF8.self)
            if id.trimmingCharacters(in: .controlCharacters).isEmpty { break }
            let sizeBytes = body[(offset + 4)..<(offset + 8)]
            let size = version == 4
                ? synchsafe(sizeBytes[sizeBytes.startIndex], sizeBytes[sizeBytes.startIndex + 1], sizeBytes[sizeBytes.startIndex + 2], sizeBytes[sizeBytes.startIndex + 3])
                : Int(be32(sizeBytes))
            let payloadStart = offset + 10, payloadEnd = payloadStart + size
            guard size >= 0, payloadEnd <= body.count else { break }
            if id == "APIC", let result = parseAPIC(Data(body[payloadStart..<payloadEnd])) { return result }
            offset = payloadEnd
        }
        return nil
    }

    private func parseAPIC(_ payload: Data) -> EmbeddedArtwork? {
        guard payload.count > 5 else { return nil }
        let encoding = payload[0]
        guard let mimeEnd = payload[1...].firstIndex(of: 0) else { return nil }
        let mime = String(decoding: payload[1..<mimeEnd], as: UTF8.self)
        var cursor = mimeEnd + 2 // NUL + picture type
        guard cursor < payload.count else { return nil }
        if encoding == 0 || encoding == 3 {
            guard let end = payload[cursor...].firstIndex(of: 0) else { return nil }
            cursor = end + 1
        } else {
            while cursor + 1 < payload.count {
                if payload[cursor] == 0, payload[cursor + 1] == 0 { cursor += 2; break }
                cursor += 2
            }
        }
        guard cursor < payload.count else { return nil }
        let data = Data(payload[cursor...])
        guard !data.isEmpty else { return nil }
        return EmbeddedArtwork(data: data, mimeType: mime.isEmpty ? "image/jpeg" : mime)
    }

    private func synchsafe(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        (Int(a & 127) << 21) | (Int(b & 127) << 14) | (Int(c & 127) << 7) | Int(d & 127)
    }
    private func le32(_ data: Data.SubSequence) -> UInt32 { data.enumerated().reduce(0) { $0 | (UInt32($1.element) << UInt32($1.offset * 8)) } }
    private func be32(_ data: Data.SubSequence) -> UInt32 { data.reduce(0) { ($0 << 8) | UInt32($1) } }
}

struct AudioFileInspector: Sendable {
    func inspect(_ url: URL) throws -> AudioTechnicalInfo {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        switch url.pathExtension.lowercased() {
        case "wav", "wave": return try inspectWAV(url, fileSize: fileSize)
        case "mp3": return try inspectMP3(url, fileSize: fileSize)
        default: throw AudioMetadataError.unsupportedFormat
        }
    }

    private func inspectWAV(_ url: URL, fileSize: Int64) throws -> AudioTechnicalInfo {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let header = try handle.read(upToCount: 12) ?? Data()
        guard header.count == 12, String(decoding: header[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: header[8..<12], as: UTF8.self) == "WAVE" else { throw AudioMetadataError.invalidWAV }
        let inputSize = try handle.seekToEnd()
        try handle.seek(toOffset: 12)
        var codec = "WAV"; var sampleRate: Int?; var depth: Int?; var channels: Int?; var byteRate: Int?; var audioBytes: Int?
        while try handle.offset() + 8 <= inputSize {
            try Task<Never, Never>.checkCancellation()
            let h = try handle.read(upToCount: 8) ?? Data(); if h.isEmpty { break }; guard h.count == 8 else { break }
            let id = String(decoding: h[0..<4], as: UTF8.self); let size = Int(le32(h[4..<8])); let payloadOffset = try handle.offset()
            let paddedEnd = payloadOffset + UInt64(size + size % 2)
            guard paddedEnd <= inputSize else { throw AudioMetadataError.invalidWAV }
            if id == "fmt ", size >= 16 {
                let data = try handle.read(upToCount: min(size, 40)) ?? Data()
                if data.count >= 16 {
                    let code = le16(data[0..<2]); channels = Int(le16(data[2..<4])); sampleRate = Int(le32(data[4..<8]));
                    byteRate = Int(le32(data[8..<12])); depth = Int(le16(data[14..<16]));
                    codec = code == 1 ? L10n.text("Uncompressed PCM") : (code == 3 ? "IEEE Float" : L10n.format("WAV codec %d", Int(code)))
                }
            } else if id == "data" { audioBytes = size }
            try handle.seek(toOffset: paddedEnd)
        }
        let duration = byteRate.flatMap { rate in audioBytes.map { Double($0) / Double(rate) } }
        let bitrate = byteRate.map { $0 * 8 / 1000 }
        return AudioTechnicalInfo(format: "WAV", codec: codec, sampleRate: sampleRate, bitDepth: depth,
                                  bitrateKbps: bitrate, channels: channels, duration: duration, fileSize: fileSize)
    }

    private func inspectMP3(_ url: URL, fileSize: Int64) throws -> AudioTechnicalInfo {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 10) ?? Data(); var offset = 0
        if prefix.count == 10, String(decoding: prefix[0..<3], as: UTF8.self) == "ID3" {
            offset = 10 + sync(prefix[6], prefix[7], prefix[8], prefix[9])
        }
        try handle.seek(toOffset: UInt64(offset)); let scan = try handle.read(upToCount: 131_072) ?? Data()
        guard scan.count >= 4 else { throw AudioMetadataError.invalidMP3 }
        for index in 0...(scan.count - 4) {
            let b1 = scan[index], b2 = scan[index + 1], b3 = scan[index + 2], b4 = scan[index + 3]
            guard b1 == 0xFF, (b2 & 0xE0) == 0xE0 else { continue }
            let versionBits = (b2 >> 3) & 0x03; let layerBits = (b2 >> 1) & 0x03
            guard versionBits != 1, layerBits == 1 else { continue }
            let bitrateIndex = Int((b3 >> 4) & 0x0F), rateIndex = Int((b3 >> 2) & 0x03)
            guard bitrateIndex > 0, bitrateIndex < 15, rateIndex < 3 else { continue }
            let isMPEG1 = versionBits == 3
            let bitrates = isMPEG1 ? [0,32,40,48,56,64,80,96,112,128,160,192,224,256,320] : [0,8,16,24,32,40,48,56,64,80,96,112,128,144,160]
            let baseRates = [44100, 48000, 32000]
            let rate = baseRates[rateIndex] / (versionBits == 3 ? 1 : (versionBits == 2 ? 2 : 4))
            let bitrate = bitrates[bitrateIndex]; let mode = Int((b4 >> 6) & 0x03); let channels = mode == 3 ? 1 : 2
            let version = versionBits == 3 ? "MPEG-1" : (versionBits == 2 ? "MPEG-2" : "MPEG-2.5")
            let variable = vbrInformation(
                in: scan, frameOffset: index, isMPEG1: isMPEG1, mono: channels == 1,
                hasCRC: (b2 & 0x01) == 0, sampleRate: rate, audioBytes: max(0, fileSize - Int64(offset))
            )
            let duration = variable?.duration
                ?? (bitrate > 0 ? Double(max(0, fileSize - Int64(offset))) * 8 / Double(bitrate * 1000) : nil)
            return AudioTechnicalInfo(
                format: "MP3", codec: "\(version) Layer III · \(variable?.label ?? "CBR")", sampleRate: rate,
                bitDepth: nil, bitrateKbps: variable?.averageBitrate ?? bitrate,
                channels: channels, duration: duration, fileSize: fileSize
            )
        }
        throw AudioMetadataError.invalidMP3
    }

    private func le16(_ data: Data.SubSequence) -> UInt16 { data.enumerated().reduce(0) { $0 | (UInt16($1.element) << UInt16($1.offset * 8)) } }
    private func le32(_ data: Data.SubSequence) -> UInt32 { data.enumerated().reduce(0) { $0 | (UInt32($1.element) << UInt32($1.offset * 8)) } }
    private func be32(_ data: Data.SubSequence) -> UInt32 { data.reduce(0) { ($0 << 8) | UInt32($1) } }
    private func sync(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int { (Int(a & 127) << 21) | (Int(b & 127) << 14) | (Int(c & 127) << 7) | Int(d & 127) }

    private func vbrInformation(
        in data: Data, frameOffset: Int, isMPEG1: Bool, mono: Bool,
        hasCRC: Bool, sampleRate: Int, audioBytes: Int64
    ) -> (duration: TimeInterval, averageBitrate: Int, label: String)? {
        let sideInfo = isMPEG1 ? (mono ? 17 : 32) : (mono ? 9 : 17)
        let xing = frameOffset + 4 + (hasCRC ? 2 : 0) + sideInfo
        if xing + 12 <= data.count {
            let marker = String(decoding: data[xing..<(xing + 4)], as: UTF8.self)
            let flags = be32(data[(xing + 4)..<(xing + 8)])
            if ["Xing", "Info"].contains(marker), flags & 0x1 != 0 {
                let frameCount = Int(be32(data[(xing + 8)..<(xing + 12)]))
                let samplesPerFrame = isMPEG1 ? 1152 : 576
                let duration = Double(frameCount * samplesPerFrame) / Double(sampleRate)
                guard duration > 0 else { return nil }
                return (duration, Int((Double(audioBytes) * 8 / duration / 1000).rounded()), marker == "Xing" ? "VBR" : "CBR")
            }
        }

        let vbri = frameOffset + 4 + 32
        if vbri + 18 <= data.count,
           String(decoding: data[vbri..<(vbri + 4)], as: UTF8.self) == "VBRI" {
            let frameCount = Int(be32(data[(vbri + 14)..<(vbri + 18)]))
            let samplesPerFrame = isMPEG1 ? 1152 : 576
            let duration = Double(frameCount * samplesPerFrame) / Double(sampleRate)
            guard duration > 0 else { return nil }
            return (duration, Int((Double(audioBytes) * 8 / duration / 1000).rounded()), "VBR")
        }
        return nil
    }
}

struct AudioMetadata: Sendable {
    let title: String
    let trackNumber: String
    let artist: String
    let album: String
    let year: Int
    let genre: String
    let bpm: Double?
    let lyrics: String?
    let artwork: Data?
    let artworkMIMEType: String?
}

enum AudioMetadataError: LocalizedError {
    case unsupportedFormat
    case invalidMP3
    case invalidWAV
    case fileTooLarge
    case metadataTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: L10n.text("Only MP3 and WAV files are supported.")
        case .invalidMP3: L10n.text("The MP3 file is invalid or unreadable.")
        case .invalidWAV: L10n.text("The WAV file is invalid or unreadable.")
        case .fileTooLarge: L10n.text("This file exceeds the standard RIFF/WAV size limit.")
        case .metadataTooLarge: L10n.text("The metadata is too large to be written safely.")
        }
    }
}

struct AudioMetadataWriter: Sendable {
    func write(source: URL, destination: URL, metadata: AudioMetadata) throws {
        try Task<Never, Never>.checkCancellation()
        let textSize = [
            metadata.title, metadata.trackNumber, metadata.artist, metadata.album,
            metadata.genre, metadata.lyrics ?? ""
        ].reduce(0) { $0 + $1.utf8.count }
        guard textSize <= 16 * 1_024 * 1_024,
              (metadata.artwork?.count ?? 0) <= 20 * 1_024 * 1_024 else {
            throw AudioMetadataError.metadataTooLarge
        }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-\(destination.lastPathComponent)")
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: temporary) } }
        switch source.pathExtension.lowercased() {
        case "mp3": try writeMP3(source: source, destination: temporary, metadata: metadata)
        case "wav", "wave": try writeWAV(source: source, destination: temporary, metadata: metadata)
        default: throw AudioMetadataError.unsupportedFormat
        }
        try Task<Never, Never>.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        committed = true
    }

    private func writeMP3(source: URL, destination: URL, metadata: AudioMetadata) throws {
        let sourceHandle = try FileHandle(forReadingFrom: source)
        defer { try? sourceHandle.close() }
        let header = try sourceHandle.read(upToCount: 10) ?? Data()
        var audioOffset: UInt64 = 0
        var preservedFrames: [Data] = []
        if header.count == 10, String(decoding: header.prefix(3), as: UTF8.self) == "ID3" {
            let size = synchsafeValue(header[6], header[7], header[8], header[9])
            guard size <= 64 * 1_024 * 1_024 else { throw AudioMetadataError.invalidMP3 }
            let body = try sourceHandle.read(upToCount: size) ?? Data()
            guard body.count == size else { throw AudioMetadataError.invalidMP3 }
            preservedFrames = preservableFrames(in: body, version: header[3], flags: header[5])
            let hasFooter = header[3] == 4 && (header[5] & 0x10) == 0x10
            audioOffset = UInt64(10 + size + (hasFooter ? 10 : 0))
        }
        let sourceSize = try sourceHandle.seekToEnd()
        guard audioOffset <= sourceSize else { throw AudioMetadataError.invalidMP3 }
        try sourceHandle.seek(toOffset: audioOffset)

        try prepareDestination(destination)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.write(contentsOf: makeID3Tag(metadata, preserving: preservedFrames))
        try copyRemaining(from: sourceHandle, to: output)
    }

    private func writeWAV(source: URL, destination: URL, metadata: AudioMetadata) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let header = try input.read(upToCount: 12) ?? Data()
        guard header.count == 12,
              String(decoding: header[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: header[8..<12], as: UTF8.self) == "WAVE" else {
            throw AudioMetadataError.invalidWAV
        }
        let inputSize = try input.seekToEnd()
        guard inputSize >= 12 else { throw AudioMetadataError.invalidWAV }
        try input.seek(toOffset: 12)

        try prepareDestination(destination)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.write(contentsOf: Data("RIFF\0\0\0\0WAVE".utf8))
        var preservedFrames: [Data] = []

        while true {
            try Task<Never, Never>.checkCancellation()
            let chunkHeader = try input.read(upToCount: 8) ?? Data()
            if chunkHeader.isEmpty { break }
            guard chunkHeader.count == 8 else { throw AudioMetadataError.invalidWAV }
            let identifier = String(decoding: chunkHeader[0..<4], as: UTF8.self)
            let size = Int(littleEndianValue(chunkHeader[4..<8]))
            let paddedSize = size + (size % 2)
            let payloadOffset = try input.offset()
            guard payloadOffset + UInt64(paddedSize) <= inputSize else {
                throw AudioMetadataError.invalidWAV
            }
            var shouldReplace = identifier == "id3 " || identifier == "ID3 "
            if shouldReplace, size >= 10, size <= 64 * 1_024 * 1_024 {
                let tag = try input.read(upToCount: size) ?? Data()
                if tag.count >= 10, String(decoding: tag.prefix(3), as: UTF8.self) == "ID3" {
                    let tagSize = min(synchsafeValue(tag[6], tag[7], tag[8], tag[9]), tag.count - 10)
                    preservedFrames.append(contentsOf: preservableFrames(
                        in: Data(tag[10..<(10 + tagSize)]), version: tag[3], flags: tag[5]
                    ))
                }
                try input.seek(toOffset: payloadOffset)
            }
            if identifier == "LIST" {
                shouldReplace = try isInfoList(input: input, size: size)
                try input.seek(toOffset: payloadOffset)
            }

            if shouldReplace {
                let currentOffset = try input.offset()
                try input.seek(toOffset: currentOffset + UInt64(paddedSize))
            } else {
                try output.write(contentsOf: chunkHeader)
                try copy(bytes: paddedSize, from: input, to: output)
            }
        }

        try output.write(contentsOf: riffChunk(id: "LIST", payload: makeInfoList(metadata)))
        try output.write(contentsOf: riffChunk(id: "id3 ", payload: makeID3Tag(metadata, preserving: preservedFrames)))
        let finalSize = try output.offset()
        guard finalSize >= 8, finalSize - 8 <= UInt64(UInt32.max) else { throw AudioMetadataError.fileTooLarge }
        try output.seek(toOffset: 4)
        try output.write(contentsOf: littleEndianData(UInt32(finalSize - 8)))
    }

    private func isInfoList(input: FileHandle, size: Int) throws -> Bool {
        guard size >= 4 else { return false }
        let marker = try input.read(upToCount: 4) ?? Data()
        return marker.count == 4 && String(decoding: marker, as: UTF8.self) == "INFO"
    }

    private func makeInfoList(_ metadata: AudioMetadata) -> Data {
        var payload = Data("INFO".utf8)
        let fields: [(String, String)] = [
            ("INAM", metadata.title), ("ITRK", metadata.trackNumber),
            ("IART", metadata.artist), ("IPRD", metadata.album),
            ("ICRD", String(metadata.year)), ("IGNR", metadata.genre),
            ("IBPM", metadata.bpm.map(formatBPM) ?? "")
        ]
        for (id, value) in fields where !value.isEmpty {
            var text = Data(value.utf8); text.append(0)
            payload.append(riffChunk(id: id, payload: text))
        }
        return payload
    }

    private func makeID3Tag(_ metadata: AudioMetadata, preserving preservedFrames: [Data]) -> Data {
        var frames = Data()
        appendTextFrame("TIT2", metadata.title, to: &frames)
        appendTextFrame("TRCK", metadata.trackNumber, to: &frames)
        appendTextFrame("TPE1", metadata.artist, to: &frames)
        appendTextFrame("TALB", metadata.album, to: &frames)
        appendTextFrame("TDRC", String(metadata.year), to: &frames)
        appendTextFrame("TCON", metadata.genre, to: &frames)
        if let bpm = metadata.bpm { appendTextFrame("TBPM", formatBPM(bpm), to: &frames) }
        if let lyrics = metadata.lyrics, !lyrics.isEmpty {
            var payload = Data([3]); payload.append(Data("und".utf8)); payload.append(0); payload.append(Data(lyrics.utf8))
            frames.append(id3Frame("USLT", payload: payload))
        }
        if let artwork = metadata.artwork {
            var payload = Data([0])
            payload.append(Data((metadata.artworkMIMEType ?? "image/jpeg").utf8)); payload.append(0)
            payload.append(3); payload.append(0); payload.append(artwork)
            frames.append(id3Frame("APIC", payload: payload))
        }
        for frame in preservedFrames { frames.append(frame) }
        var tag = Data("ID3".utf8)
        tag.append(contentsOf: [4, 0, 0])
        tag.append(contentsOf: synchsafeBytes(frames.count))
        tag.append(frames)
        return tag
    }

    private func appendTextFrame(_ id: String, _ value: String, to frames: inout Data) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var payload = Data([3]); payload.append(Data(value.utf8))
        frames.append(id3Frame(id, payload: payload))
    }

    private func id3Frame(_ id: String, payload: Data) -> Data {
        var frame = Data(id.utf8)
        frame.append(contentsOf: synchsafeBytes(payload.count))
        frame.append(contentsOf: [0, 0]); frame.append(payload)
        return frame
    }

    private func preservableFrames(in body: Data, version: UInt8, flags: UInt8) -> [Data] {
        guard (version == 3 || version == 4), flags & 0x80 == 0 else { return [] }
        let replaced: Set<String> = [
            "TIT2", "TRCK", "TPE1", "TALB", "TYER", "TDRC", "TCON", "TBPM", "USLT", "APIC"
        ]
        var offset = 0
        if flags & 0x40 != 0, body.count >= 4 {
            let extendedSize = version == 4
                ? synchsafeValue(body[0], body[1], body[2], body[3])
                : Int(bigEndianValue(body[0..<4])) + 4
            offset = min(max(0, extendedSize), body.count)
        }
        var frames: [Data] = []
        while offset + 10 <= body.count {
            let id = String(decoding: body[offset..<(offset + 4)], as: UTF8.self)
            guard id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { break }
            let size = version == 4
                ? synchsafeValue(body[offset + 4], body[offset + 5], body[offset + 6], body[offset + 7])
                : Int(bigEndianValue(body[(offset + 4)..<(offset + 8)]))
            let payloadStart = offset + 10, payloadEnd = payloadStart + size
            guard size >= 0, payloadEnd <= body.count else { break }
            let hasUnsupportedFlags = body[offset + 8] != 0 || body[offset + 9] != 0
            if !replaced.contains(id), !hasUnsupportedFlags {
                frames.append(id3Frame(id, payload: Data(body[payloadStart..<payloadEnd])))
            }
            offset = payloadEnd
        }
        return frames
    }

    private func riffChunk(id: String, payload: Data) -> Data {
        var chunk = Data(id.utf8.prefix(4)); chunk.append(littleEndianData(UInt32(payload.count))); chunk.append(payload)
        if payload.count % 2 == 1 { chunk.append(0) }
        return chunk
    }

    private func prepareDestination(_ url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func copyRemaining(from input: FileHandle, to output: FileHandle) throws {
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try Task<Never, Never>.checkCancellation()
            try output.write(contentsOf: data)
        }
    }

    private func copy(bytes: Int, from input: FileHandle, to output: FileHandle) throws {
        var remaining = bytes
        while remaining > 0 {
            try Task<Never, Never>.checkCancellation()
            let data = try input.read(upToCount: min(remaining, 1_048_576)) ?? Data()
            guard !data.isEmpty else { throw AudioMetadataError.invalidWAV }
            try output.write(contentsOf: data); remaining -= data.count
        }
    }

    private func formatBPM(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func synchsafeValue(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        (Int(a & 0x7F) << 21) | (Int(b & 0x7F) << 14) | (Int(c & 0x7F) << 7) | Int(d & 0x7F)
    }

    private func synchsafeBytes(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    private func bigEndianData(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    private func littleEndianData(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private func littleEndianValue(_ data: Data.SubSequence) -> UInt32 {
        data.enumerated().reduce(0) { $0 | (UInt32($1.element) << UInt32($1.offset * 8)) }
    }
    private func bigEndianValue(_ data: Data.SubSequence) -> UInt32 {
        data.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
