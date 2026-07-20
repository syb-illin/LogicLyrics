import AppKit
import Foundation

@MainActor
final class SunoViewModel: ObservableObject {
    @Published var referenceArtist = ""
    @Published var allowsFemaleBackingVocals = false
    @Published var generatedPrompt = ""
    @Published var errorMessage: String?
    @Published var copiedField: String?
    private var feedbackTask: Task<Void, Never>?

    init(referenceArtist: String = "", allowsFemaleBackingVocals: Bool = false, generatedPrompt: String = "") {
        self.referenceArtist = referenceArtist
        self.allowsFemaleBackingVocals = allowsFemaleBackingVocals
        self.generatedPrompt = generatedPrompt
    }

    var hasPrompt: Bool { !generatedPrompt.isEmpty }

    @discardableResult
    func generatePrompt(from lyrics: String, bpmText: String, musicalKey: String) -> String? {
        let artist = referenceArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artist.isEmpty else {
            errorMessage = L10n.text("Enter a reference band or artist.")
            return nil
        }
        guard !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = L10n.text("No lyrics are loaded.")
            return nil
        }
        let normalizedBPM = bpmText.replacingOccurrences(of: ",", with: ".")
        guard let bpm = Double(normalizedBPM), (20...400).contains(bpm) else {
            errorMessage = L10n.text("Enter a valid BPM between 20 and 400.")
            return nil
        }
        let key = musicalKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = L10n.text("Enter the song key.")
            return nil
        }
        let bpmLabel = bpm.rounded() == bpm ? String(Int(bpm)) : String(format: "%.2f", bpm)

        let backingRule = allowsFemaleBackingVocals
            ? "Female backing vocals are allowed only as subtle harmonies, responses, textures or counterlines. They must never become the lead or replace the male baritone."
            : "Do not use any female voice. Backing vocals may use only subtle male low-register harmonies."

        generatedPrompt = """
        You are preparing an original song for Suno AI.

        REFERENCE ARTIST OR BAND
        \(artist)

        Translate this reference into broad musical characteristics only: genre family, tempo range,
        energy, instrumentation, arrangement, vocal profile, mix character and production era.
        Do not imitate or reproduce signature melodies, lyrics, titles or distinctive protected elements.
        Do not include the artist name in the final Suno style fields.

        REQUIRED OUTPUT
        Return exactly these three sections, with no introduction and no commentary.
        Put the content of EACH section in its own fenced `text` code block so ChatGPT or Gemini
        displays a separate built-in Copy action for Styles, Styles to Exclude and Lyrics.
        Never combine the three fields into one code block.

        ## Styles
        ```text
        Must begin exactly with: \(bpmLabel) BPM, \(key).
        Then provide a compact comma-separated Suno Style of Music prompt only.
        ```

        ## Styles to Exclude
        ```text
        A compact comma-separated Suno negative style prompt only.
        ```

        ## Lyrics
        ```text
        The complete original lyrics, preserving every lyric line and existing section marker,
        enhanced only with concise Suno arrangement and performance instructions in square brackets.
        ```

        Do not put explanations, labels or quotation marks inside the three code blocks.

        NON-NEGOTIABLE VOCAL IDENTITY
        - The user will select their verified Suno Voice profile.
        - Use one single consistent male baritone lead from the first line to the last.
        - Preserve the real vocal grain, timbre, natural formants, diction and phrasing.
        - Natural chest voice only, comfortable baritone register, grounded and realistically singable.
        - No falsetto, head voice, high notes, high belting, whistle register or octave-up doubles.
        - No screaming, shouting, growling, harsh vocals, gutturals or artificial vocal distortion.
        - No fast melismas, elaborate runs, ornamental riffs, excessive ad-libs, wide octave leaps,
          virtuosic sustains, showy cadenzas or vocal acrobatics.
        - Do not improve the singer into an unrealistic virtuoso performance.
        - No voice morphing, gender shift, alternate singer, character voice or replacement vocalist.
        - Back vocals may support but never replace, mask, morph or alter the identity of the lead.
        - \(backingRule)
        - Put a global vocal direction before the first song section in LYRICS.
        - Reinforce these constraints in STYLES and put every prohibited behavior in STYLES TO EXCLUDE.
        - Vocal fidelity takes priority over the reference artist.

        NON-NEGOTIABLE MUSICAL METADATA
        - The Styles block MUST start with the exact project metadata: \(bpmLabel) BPM, \(key).
        - Never omit, estimate, reinterpret or change this BPM or key.

        ORIGINAL LYRICS
        \(lyrics)
        """
        return generatedPrompt
    }

    func copyPrompt() {
        copy(generatedPrompt, field: "prompt")
    }

    func copyAndOpenChatGPT() {
        copyAndOpen(urlString: "https://chatgpt.com/", field: "chatgpt")
    }

    func copyAndOpenGemini() {
        copyAndOpen(urlString: "https://gemini.google.com/app", field: "gemini")
    }

    private func copyAndOpen(urlString: String, field: String) {
        guard hasPrompt, let url = URL(string: urlString) else { return }
        copy(generatedPrompt, field: field)
        NSWorkspace.shared.open(url)
    }

    private func copy(_ text: String, field: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedField = field
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task<Never, Never>.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            if self?.copiedField == field { self?.copiedField = nil }
        }
    }
}
