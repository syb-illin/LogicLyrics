import Foundation

/// Pure title-search policy shared by the sidebar and regression tests.
/// Lyrics are intentionally excluded: the sidebar represents Logic projects,
/// so a query must only match the project name shown to the user.
enum HistorySearch {
    static func filter(
        _ entries: [SongHistoryEntry],
        query rawQuery: String,
        onlyWithoutLyrics: Bool
    ) -> [SongHistoryEntry] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            let matchesTitle = query.isEmpty
                || entry.projectName.localizedCaseInsensitiveContains(query)
            let matchesLyricsState = !onlyWithoutLyrics
                || entry.sourceLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return matchesTitle && matchesLyricsState
        }
    }
}
