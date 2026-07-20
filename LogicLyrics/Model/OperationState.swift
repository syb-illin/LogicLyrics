import Foundation

enum OperationState: Equatable, Sendable {
    case idle
    case running(message: String, startedAt: Date)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var message: String? {
        if case .running(let message, _) = self { return message }
        return nil
    }
}

struct UserAlert: Identifiable, Equatable, Sendable {
    enum Kind: Sendable, Equatable { case error, warning, success }
    let id = UUID()
    let kind: Kind
    let title: String
    let message: String

    static func error(_ error: Error, context: String) -> UserAlert {
        UserAlert(kind: .error, title: context, message: error.localizedDescription)
    }
}
