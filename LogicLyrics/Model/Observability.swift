import AppKit
import Foundation
import OSLog

enum AppLog {
    private static let subsystem = "com.local.LogicLyrics"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let projects = Logger(subsystem: subsystem, category: "projects")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let updates = Logger(subsystem: subsystem, category: "updates")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")

    static var subsystemIdentifier: String { subsystem }
}

@MainActor
enum AppDiagnostics {
    static func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snapshot, forType: .string)
        AppLog.lifecycle.info("Privacy-safe diagnostics copied")
    }

    static var snapshot: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let localization = Bundle.main.preferredLocalizations.first ?? "unknown"
        let system = """
        Logic Lyrics Diagnostics
        Version: \(version) (\(build))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(architecture)
        App localization: \(localization)
        Locale: \(Locale.current.identifier)
        Processor count: \(ProcessInfo.processInfo.processorCount)
        Physical memory: \(ProcessInfo.processInfo.physicalMemory) bytes
        """
        let events = recentEvents()
        guard !events.isEmpty else { return system }
        return system + "\n\nRecent privacy-safe events (maximum 200):\n" + events.joined(separator: "\n")
    }

    private static func recentEvents() -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let start = store.position(date: Date().addingTimeInterval(-30 * 60))
            let entries = try store.getEntries(at: start)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == AppLog.subsystemIdentifier }
            let formatter = ISO8601DateFormatter()
            return Array(entries.suffix(200)).map { entry in
                "\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)"
            }
        } catch {
            let errorType = String(describing: type(of: error))
            AppLog.diagnostics.error("Diagnostic log collection failed error_type=\(errorType, privacy: .public)")
            return []
        }
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}
