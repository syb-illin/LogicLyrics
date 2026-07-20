import Foundation

struct SongHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var projectName: String
    var projectPath: String
    var noteKey: String
    var alternative: String
    var lyrics: String
    var prompt: String
    var referenceArtist: String
    var allowsFemaleBackingVocals: Bool
    var bpm: Double?
    var musicalKey: String?
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, projectName, projectPath, noteKey, alternative, lyrics, prompt
        case referenceArtist, allowsFemaleBackingVocals, bpm, musicalKey, createdAt, updatedAt
    }

    init(
        id: UUID, projectName: String, projectPath: String, noteKey: String, alternative: String,
        lyrics: String, prompt: String, referenceArtist: String, allowsFemaleBackingVocals: Bool,
        bpm: Double?, musicalKey: String?, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.projectName = projectName
        self.projectPath = projectPath
        self.noteKey = noteKey
        self.alternative = alternative
        self.lyrics = lyrics
        self.prompt = prompt
        self.referenceArtist = referenceArtist
        self.allowsFemaleBackingVocals = allowsFemaleBackingVocals
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectName = try values.decodeIfPresent(String.self, forKey: .projectName) ?? "Projet Logic"
        projectPath = try values.decodeIfPresent(String.self, forKey: .projectPath) ?? ""
        noteKey = try values.decodeIfPresent(String.self, forKey: .noteKey) ?? "legacy"
        alternative = try values.decodeIfPresent(String.self, forKey: .alternative) ?? ""
        lyrics = try values.decodeIfPresent(String.self, forKey: .lyrics) ?? ""
        prompt = try values.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        referenceArtist = try values.decodeIfPresent(String.self, forKey: .referenceArtist) ?? ""
        allowsFemaleBackingVocals = try values.decodeIfPresent(Bool.self, forKey: .allowsFemaleBackingVocals) ?? false
        bpm = try values.decodeIfPresent(Double.self, forKey: .bpm)
        musicalKey = try values.decodeIfPresent(String.self, forKey: .musicalKey)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}
