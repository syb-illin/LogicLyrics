import Foundation

struct LyricSection: Identifiable, Hashable, Sendable {
    /// Stable within one lyrics document, avoiding needless SwiftUI row churn
    /// when the same Project Notes are rendered again.
    let id: Int
    let label: String
    let content: String

    var fullText: String { "[\(label)]\n\(content)" }
}

enum LyricSectionParser {
    // Both patterns are compile-time constants covered by regression tests.
    // A source-code typo must fail immediately during development.
    private static let adjacentMarkers = try! NSRegularExpression(pattern: #"\]\s*\["#)
    private static let marker = try! NSRegularExpression(pattern: #"(?m)^\s*\[([^\]\r\n]+)\]\s*$"#)

    private static let structuralPrefixes = [
        "verse", "chorus", "pre-chorus", "prechorus", "bridge", "intro", "outro",
        "hook", "refrain", "post-chorus", "post chorus", "interlude", "breakdown",
        "instrumental", "solo", "coda", "ending"
    ]
    private static let performanceDirectiveTerms = [
        "vocal", "vocals", "singing", "spoken", "whisper", "falsetto", "baritone",
        "soprano", "alto", "tenor", "male", "female", "duet", "harmony", "harmonies",
        "backing", "guitar", "piano", "synth", "drum", "bass", "strings", "brass",
        "clean", "distorted", "soft", "loud", "energetic", "melodic", "production",
        "tempo", "bpm", "key", "fade", "reverb", "delay"
    ]

    // Unknown labels remain valid for custom song structures, while common
    // Suno performance/production directives remain part of the section body.
    static func parse(_ lyrics: String) -> [LyricSection] {
        let original = lyrics as NSString
        let normalized = adjacentMarkers.stringByReplacingMatches(
            in: lyrics, range: NSRange(location: 0, length: original.length), withTemplate: "]\n["
        )
        let source = normalized as NSString
        let matches = marker
            .matches(in: normalized, range: NSRange(location: 0, length: source.length))
            .filter { match in
                isStructuralLabel(source.substring(with: match.range(at: 1)))
            }
        guard !matches.isEmpty else { return [] }

        return matches.enumerated().map { index, match in
            let label = source.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyStart = NSMaxRange(match.range)
            let bodyEnd = index + 1 < matches.count ? matches[index + 1].range.location : source.length
            let body = source.substring(with: NSRange(location: bodyStart, length: max(0, bodyEnd - bodyStart)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return LyricSection(id: index, label: label, content: body)
        }
    }

    private static func isStructuralLabel(_ rawLabel: String) -> Bool {
        let label = rawLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        guard !label.isEmpty else { return false }
        if structuralPrefixes.contains(where: { label.hasPrefix($0) }) { return true }
        let words = Set(label.split(whereSeparator: { !$0.isLetter }).map(String.init))
        return performanceDirectiveTerms.allSatisfy { !words.contains($0) }
    }
}
