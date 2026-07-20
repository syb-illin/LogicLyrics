import AppKit
import SwiftUI

@main
struct LogicLyricsApp: App {
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
                Button("À propos de Logic Lyrics") {
                    let credits = NSAttributedString(
                        string: "Extrait les paroles des Notes de projet Logic Pro et prépare des prompts Suno AI respectueux de ta voix.",
                        attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                    )
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Logic Lyrics",
                        .applicationVersion: Self.versionLabel,
                        .credits: credits
                    ])
                }
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
