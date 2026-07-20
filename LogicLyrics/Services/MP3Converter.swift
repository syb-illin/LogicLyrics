import Foundation

enum MP3EncodingMode: String, CaseIterable, Identifiable, Sendable {
    case cbr
    case vbr
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cbr: L10n.text("Constant bitrate (CBR)")
        case .vbr: L10n.text("Variable quality (VBR)")
        }
    }
}

enum MP3Bitrate: Int, CaseIterable, Identifiable, Sendable {
    case kbps128 = 128, kbps192 = 192, kbps256 = 256, kbps320 = 320
    var id: Int { rawValue }
    var label: String { "\(rawValue) kb/s" }
}

enum MP3VBRQuality: Int, CaseIterable, Identifiable, Sendable {
    case v0 = 0, v2 = 2, v4 = 4
    var id: Int { rawValue }
    var label: String { "V\(rawValue)" }
}

enum MP3SampleRate: String, CaseIterable, Identifiable, Sendable {
    case source
    case hz44100
    case hz48000
    var id: String { rawValue }
    var lameValue: String? { self == .hz44100 ? "44.1" : (self == .hz48000 ? "48" : nil) }
    var label: String {
        switch self {
        case .source: L10n.text("Same as source")
        case .hz44100: "44.1 kHz"
        case .hz48000: "48 kHz"
        }
    }
}

struct MP3EncodingSettings: Sendable {
    let mode: MP3EncodingMode
    let bitrate: MP3Bitrate
    let vbrQuality: MP3VBRQuality
    let sampleRate: MP3SampleRate
}

enum MP3ConversionError: LocalizedError {
    case encoderMissing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .encoderMissing: L10n.text("The LAME MP3 engine is missing from the application. Run BUILD.command again.")
        case .failed(let details): L10n.format("MP3 conversion failed. %@", details)
        }
    }
}

struct MP3Converter: Sendable {
    func convert(wav: URL, destination: URL, settings: MP3EncodingSettings) throws {
        guard let executable = Bundle.main.url(forResource: "lame", withExtension: nil),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw MP3ConversionError.encoderMissing
        }
        let process = Process()
        let diagnostics = Pipe()
        process.executableURL = executable
        var arguments = ["--silent", "-q", "0", "-m", "j"]
        if settings.mode == .cbr {
            arguments += ["--cbr", "-b", String(settings.bitrate.rawValue)]
        } else {
            arguments += ["-V", String(settings.vbrQuality.rawValue)]
        }
        if let sampleRate = settings.sampleRate.lameValue { arguments += ["--resample", sampleRate] }
        arguments += [wav.path, destination.path]
        process.arguments = arguments
        process.standardError = diagnostics
        try process.run()
        while process.isRunning {
            if Task<Never, Never>.isCancelled {
                process.terminate()
                process.waitUntilExit()
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.08)
        }
        guard process.terminationStatus == 0 else {
            let data = diagnostics.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw MP3ConversionError.failed(message)
        }
    }
}
