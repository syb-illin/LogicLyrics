import Foundation

/// Narrow dependency boundary used by `ProjectViewModel`. Keeping the reader
/// injectable makes the UI deterministic in tests without introducing a
/// general-purpose service container for this intentionally focused app.
protocol LogicProjectReading: Sendable {
    func readProject(at projectURL: URL) throws -> LogicProjectReader.Result
    func readProject(at projectURL: URL, preferredAlternative: String?) throws -> LogicProjectReader.Result
    func projectStateToken(at projectURL: URL, preferredAlternative: String?) throws -> String
}

extension LogicProjectReader: LogicProjectReading {}
