import Foundation

struct SongHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var projectName: String
    var projectPath: String
    private(set) var projectFileID: String?
    private(set) var projectBookmark: Data?
    var noteKey: String
    var alternative: String
    private(set) var sourceLyrics: String
    private(set) var editedLyrics: String?
    private(set) var recoveredLyrics: [String]
    private(set) var needsSourceReconciliation: Bool
    var prompt: String
    var referenceArtist: String
    var allowsFemaleBackingVocals: Bool
    var bpm: Double?
    var musicalKey: String?
    let createdAt: Date
    var updatedAt: Date

    /// The history detail favors the user's local edit while retaining the
    /// latest text extracted from Logic as an independent source snapshot.
    var lyrics: String { editedLyrics ?? sourceLyrics }
    var hasLocalEdits: Bool { editedLyrics != nil }

    var searchableLyrics: String {
        ([sourceLyrics, editedLyrics].compactMap { $0 } + recoveredLyrics)
            .joined(separator: "\n")
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectName, projectPath, projectFileID, projectBookmark, noteKey, alternative
        case lyrics // Schema 1–2 compatibility and downgrade safety.
        case sourceLyrics, editedLyrics, recoveredLyrics, needsSourceReconciliation
        case prompt, referenceArtist, allowsFemaleBackingVocals, bpm, musicalKey, createdAt, updatedAt
    }

    init(
        id: UUID, projectName: String, projectPath: String, noteKey: String, alternative: String,
        lyrics: String, prompt: String, referenceArtist: String, allowsFemaleBackingVocals: Bool,
        bpm: Double?, musicalKey: String?, createdAt: Date, updatedAt: Date,
        projectFileID: String? = nil, projectBookmark: Data? = nil
    ) {
        self.id = id
        self.projectName = projectName
        self.projectPath = projectPath
        self.projectFileID = projectFileID
        self.projectBookmark = projectBookmark
        self.noteKey = noteKey
        self.alternative = alternative
        sourceLyrics = lyrics
        editedLyrics = nil
        recoveredLyrics = []
        needsSourceReconciliation = false
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
        projectName = try values.decodeIfPresent(String.self, forKey: .projectName) ?? L10n.text("Logic Project")
        projectPath = try values.decodeIfPresent(String.self, forKey: .projectPath) ?? ""
        projectFileID = try values.decodeIfPresent(String.self, forKey: .projectFileID)
        projectBookmark = try values.decodeIfPresent(Data.self, forKey: .projectBookmark)
        noteKey = try values.decodeIfPresent(String.self, forKey: .noteKey) ?? "legacy"
        alternative = try values.decodeIfPresent(String.self, forKey: .alternative) ?? ""

        if let source = try values.decodeIfPresent(String.self, forKey: .sourceLyrics) {
            sourceLyrics = source
            needsSourceReconciliation = try values.decodeIfPresent(
                Bool.self, forKey: .needsSourceReconciliation
            ) ?? false
        } else {
            sourceLyrics = try values.decodeIfPresent(String.self, forKey: .lyrics) ?? ""
            // Older schemas did not distinguish Logic source text from an edit
            // or from the technical RTF false positives fixed in v2.2.4.
            needsSourceReconciliation = true
        }
        editedLyrics = try values.decodeIfPresent(String.self, forKey: .editedLyrics)
        recoveredLyrics = try values.decodeIfPresent([String].self, forKey: .recoveredLyrics) ?? []
        prompt = try values.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        referenceArtist = try values.decodeIfPresent(String.self, forKey: .referenceArtist) ?? ""
        allowsFemaleBackingVocals = try values.decodeIfPresent(Bool.self, forKey: .allowsFemaleBackingVocals) ?? false
        bpm = try values.decodeIfPresent(Double.self, forKey: .bpm)
        musicalKey = try values.decodeIfPresent(String.self, forKey: .musicalKey)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        normalizeCollections()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(projectName, forKey: .projectName)
        try values.encode(projectPath, forKey: .projectPath)
        try values.encodeIfPresent(projectFileID, forKey: .projectFileID)
        try values.encodeIfPresent(projectBookmark, forKey: .projectBookmark)
        try values.encode(noteKey, forKey: .noteKey)
        try values.encode(alternative, forKey: .alternative)
        try values.encode(lyrics, forKey: .lyrics)
        try values.encode(sourceLyrics, forKey: .sourceLyrics)
        try values.encodeIfPresent(editedLyrics, forKey: .editedLyrics)
        try values.encode(recoveredLyrics, forKey: .recoveredLyrics)
        try values.encode(needsSourceReconciliation, forKey: .needsSourceReconciliation)
        try values.encode(prompt, forKey: .prompt)
        try values.encode(referenceArtist, forKey: .referenceArtist)
        try values.encode(allowsFemaleBackingVocals, forKey: .allowsFemaleBackingVocals)
        try values.encodeIfPresent(bpm, forKey: .bpm)
        try values.encodeIfPresent(musicalKey, forKey: .musicalKey)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }

    mutating func reconcileSourceLyrics(_ value: String) {
        let previousSource = sourceLyrics
        sourceLyrics = value
        needsSourceReconciliation = false
        if previousSource != value { recover(previousSource) }
        if editedLyrics == sourceLyrics { editedLyrics = nil }
        normalizeCollections()
    }

    mutating func applyLocalEdit(_ value: String) {
        editedLyrics = value == sourceLyrics ? nil : value
        normalizeCollections()
    }

    mutating func recover(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != sourceLyrics, cleaned != editedLyrics,
              !recoveredLyrics.contains(cleaned) else { return }
        recoveredLyrics.append(cleaned)
    }

    mutating func replaceRecoveredLyrics(_ values: [String]) {
        recoveredLyrics = values
        normalizeCollections()
    }

    mutating func replaceEditedLyrics(_ value: String?) {
        editedLyrics = value
        normalizeCollections()
    }

    mutating func restoreRevision(_ value: String) {
        let previousEdit = editedLyrics
        editedLyrics = nil
        recoveredLyrics.removeAll { $0 == value }
        if let previousEdit { recover(previousEdit) }
        applyLocalEdit(value)
    }

    mutating func revertToSource() {
        let previousEdit = editedLyrics
        editedLyrics = nil
        if let previousEdit { recover(previousEdit) }
        normalizeCollections()
    }

    mutating func updateProjectLocation(path: String, fileID: String?, bookmark: Data?) {
        projectPath = path
        projectFileID = fileID
        projectBookmark = bookmark
    }

    func exportableCopy() -> SongHistoryEntry {
        var copy = self
        // Security-scoped bookmarks and filesystem IDs are machine-specific
        // capabilities and must never leave the Mac in a portable archive.
        copy.projectBookmark = nil
        copy.projectFileID = nil
        return copy
    }

    mutating func markSourceForReconciliation(_ value: Bool) {
        needsSourceReconciliation = value
    }

    private mutating func normalizeCollections() {
        if editedLyrics == sourceLyrics { editedLyrics = nil }
        var seen = Set<String>()
        recoveredLyrics = recoveredLyrics.compactMap { value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned != sourceLyrics, cleaned != editedLyrics,
                  seen.insert(cleaned).inserted else { return nil }
            return cleaned
        }
    }
}
