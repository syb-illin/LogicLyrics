import Foundation

/// Narrow dependency boundary used by `ProjectViewModel`. Keeping the reader
/// injectable makes the UI deterministic in tests without introducing a
/// general-purpose service container for this intentionally focused app.
protocol LogicProjectReading: Sendable {
    func readProject(at projectURL: URL) throws -> LogicProjectReader.Result
}

extension LogicProjectReader: LogicProjectReading {}
