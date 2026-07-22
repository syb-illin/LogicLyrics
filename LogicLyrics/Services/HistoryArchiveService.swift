import Foundation

private struct PortableHistoryArchive: Codable, Sendable {
    let format: String
    let version: Int
    let exportedAt: Date
    let entries: [SongHistoryEntry]
}

enum HistoryArchiveError: LocalizedError, Sendable {
    case tooLarge
    case invalidFormat
    case unsupportedVersion(Int)
    case tooManyEntries
    case invalidEntry

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            L10n.text("The history archive is too large to import safely.")
        case .invalidFormat:
            L10n.text("This file is not a valid Logic Lyrics history archive.")
        case .unsupportedVersion(let version):
            L10n.format("This history archive requires a newer app version (format %d).", version)
        case .tooManyEntries:
            L10n.text("The history archive contains too many songs to import safely.")
        case .invalidEntry:
            L10n.text("The history archive contains an invalid or oversized song entry.")
        }
    }
}

struct HistoryArchiveService: Sendable {
    static let fileExtension = "logiclyrics-history"
    private static let format = "com.logiclyrics.history"
    private static let currentVersion = 1
    private static let maximumArchiveBytes = 50 * 1_024 * 1_024
    private static let maximumEntries = 10_000
    private static let maximumTextCharacters = 2_000_000

    func write(_ entries: [SongHistoryEntry], to destination: URL) throws {
        let didAccess = destination.startAccessingSecurityScopedResource()
        defer { if didAccess { destination.stopAccessingSecurityScopedResource() } }
        let archive = PortableHistoryArchive(
            format: Self.format,
            version: Self.currentVersion,
            exportedAt: Date(),
            entries: entries.map { $0.exportableCopy() }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= Self.maximumArchiveBytes else { throw HistoryArchiveError.tooLarge }
        try data.write(to: destination, options: .atomic)
    }

    func read(from source: URL) throws -> [SongHistoryEntry] {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= Self.maximumArchiveBytes else {
            throw HistoryArchiveError.tooLarge
        }
        let data = try Data(contentsOf: source, options: [.mappedIfSafe])
        guard data.count <= Self.maximumArchiveBytes else { throw HistoryArchiveError.tooLarge }

        let decoder = JSONDecoder()
        let entries: [SongHistoryEntry]
        if let archive = try? decoder.decode(PortableHistoryArchive.self, from: data) {
            guard archive.format == Self.format else { throw HistoryArchiveError.invalidFormat }
            guard archive.version <= Self.currentVersion else {
                throw HistoryArchiveError.unsupportedVersion(archive.version)
            }
            entries = archive.entries
        } else if let legacyEntries = try? decoder.decode([SongHistoryEntry].self, from: data) {
            entries = legacyEntries
        } else {
            throw HistoryArchiveError.invalidFormat
        }

        try validate(entries)
        return entries.map { $0.exportableCopy() }
    }

    private func validate(_ entries: [SongHistoryEntry]) throws {
        guard entries.count <= Self.maximumEntries else { throw HistoryArchiveError.tooManyEntries }
        for entry in entries {
            let texts = [
                entry.projectName, entry.projectPath, entry.noteKey, entry.alternative,
                entry.sourceLyrics, entry.editedLyrics ?? "", entry.prompt, entry.referenceArtist
            ] + entry.recoveredLyrics
            guard texts.allSatisfy({ $0.count <= Self.maximumTextCharacters }) else {
                throw HistoryArchiveError.invalidEntry
            }
        }
    }
}
