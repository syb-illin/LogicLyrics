import AppKit
import SwiftUI

@main
struct LogicLyricsApp: App {
    init() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let localization = Bundle.main.preferredLocalizations.first ?? "unknown"
        AppLog.lifecycle.notice("Application launched version=\(version, privacy: .public) build=\(build, privacy: .public) localization=\(localization, privacy: .public)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 650)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L10n.text("About Logic Lyrics")) {
                    let credits = NSAttributedString(
                        string: L10n.text("Extracts lyrics from Logic Pro Project Notes and prepares Suno AI prompts that preserve your vocal identity."),
                        attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                    )
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Logic Lyrics",
                        .applicationVersion: Self.versionLabel,
                        .credits: credits
                    ])
                }
            }
            CommandMenu(L10n.text("Diagnostics")) {
                Button(L10n.text("Copy System Diagnostics")) {
                    AppDiagnostics.copyToPasteboard()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }
        }

        Settings {
            MetadataSettingsView()
        }
    }

    private static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (build \(build))"
    }
}
