import Foundation

/// One durable snapshot per Logic project. Schema 5 deliberately stores only
/// information produced by the read-only project-reader workflow.
struct SongHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var projectName: String
    var projectPath: String
    private(set) var projectFileID: String?
    private(set) var projectBookmark: Data?
    var alternative: String
    private(set) var sourceLyrics: String
    var bpm: Double?
    var musicalKey: String?
    var diagnostics: ExtractionDiagnostics?
    var sourceStateToken: String?
    var isPinned: Bool
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, projectName, projectPath, projectFileID, projectBookmark, alternative
        case lyrics, sourceLyrics, editedLyrics // Legacy schema 1–4 input only.
        case bpm, musicalKey, diagnostics, sourceStateToken, isPinned, createdAt, updatedAt
    }

    init(
        id: UUID,
        projectName: String,
        projectPath: String,
        alternative: String,
        sourceLyrics: String,
        bpm: Double?,
        musicalKey: String?,
        diagnostics: ExtractionDiagnostics? = nil,
        sourceStateToken: String? = nil,
        isPinned: Bool = false,
        createdAt: Date,
        updatedAt: Date,
        projectFileID: String? = nil,
        projectBookmark: Data? = nil
    ) {
        self.id = id
        self.projectName = projectName
        self.projectPath = projectPath
        self.projectFileID = projectFileID
        self.projectBookmark = projectBookmark
        self.alternative = alternative
        self.sourceLyrics = sourceLyrics
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.diagnostics = diagnostics
        self.sourceStateToken = sourceStateToken
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectName = try values.decodeIfPresent(String.self, forKey: .projectName)
            ?? L10n.text("Logic Project")
        projectPath = try values.decodeIfPresent(String.self, forKey: .projectPath) ?? ""
        projectFileID = try values.decodeIfPresent(String.self, forKey: .projectFileID)
        projectBookmark = try values.decodeIfPresent(Data.self, forKey: .projectBookmark)
        alternative = try values.decodeIfPresent(String.self, forKey: .alternative) ?? ""

        // Prefer the last text verified against Logic. Very old files only had
        // `lyrics`; edited schema-4 text is intentionally not promoted to a
        // Logic source snapshot. The untouched schema backup preserves it.
        sourceLyrics = try values.decodeIfPresent(String.self, forKey: .sourceLyrics)
            ?? values.decodeIfPresent(String.self, forKey: .lyrics)
            ?? values.decodeIfPresent(String.self, forKey: .editedLyrics)
            ?? ""
        bpm = try values.decodeIfPresent(Double.self, forKey: .bpm)
        musicalKey = try values.decodeIfPresent(String.self, forKey: .musicalKey)
        diagnostics = try values.decodeIfPresent(ExtractionDiagnostics.self, forKey: .diagnostics)
        sourceStateToken = try values.decodeIfPresent(String.self, forKey: .sourceStateToken)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    mutating func updateSource(
        lyrics: String,
        alternative: String,
        bpm: Double?,
        musicalKey: String?,
        diagnostics: ExtractionDiagnostics?,
        sourceStateToken: String?
    ) {
        sourceLyrics = lyrics
        self.alternative = alternative
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.diagnostics = diagnostics
        self.sourceStateToken = sourceStateToken
    }

    mutating func updateProjectLocation(path: String, fileID: String?, bookmark: Data?) {
        projectPath = path
        projectFileID = fileID
        projectBookmark = bookmark
    }
}
