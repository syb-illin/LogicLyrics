import AppKit
import Foundation
import OSLog

enum AppLog {
    private static let subsystem = "com.local.LogicLyrics"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let projects = Logger(subsystem: subsystem, category: "projects")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let updates = Logger(subsystem: subsystem, category: "updates")
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
        return """
        Logic Lyrics Diagnostics
        Version: \(version) (\(build))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(architecture)
        App localization: \(localization)
        Locale: \(Locale.current.identifier)
        Processor count: \(ProcessInfo.processInfo.processorCount)
        """
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
