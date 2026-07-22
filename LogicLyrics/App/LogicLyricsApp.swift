import AppKit
import SwiftUI

@main
@MainActor
struct LogicLyricsApp: App {
    @StateObject private var updater = UpdateService()

    init() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let localization = Bundle.main.preferredLocalizations.first ?? "unknown"
        AppLog.lifecycle.notice("Application launched version=\(version, privacy: .public) build=\(build, privacy: .public) localization=\(localization, privacy: .public)")
    }

    var body: some Scene {
        Window("Logic Lyrics", id: "main") {
            ContentView()
                .environmentObject(updater)
                .frame(minWidth: 820, minHeight: 620)
                .preferredColorScheme(.dark)
                .background(WindowSizeOverride(size: Self.requestedUITestWindowSize))
        }
        .windowStyle(.titleBar)
        .defaultSize(width: Self.initialWindowSize.width, height: Self.initialWindowSize.height)
        .defaultPosition(.center)
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
            AppSettingsView()
                .environmentObject(updater)
        }
    }

    private static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (build \(build))"
    }

    private static var initialWindowSize: CGSize {
        requestedUITestWindowSize ?? CGSize(width: 1_180, height: 780)
    }

    private static var requestedUITestWindowSize: CGSize? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-test-compact-window") {
            return CGSize(width: 860, height: 640)
        }
        if arguments.contains("--ui-test-large-window") {
            return CGSize(width: 1_440, height: 900)
        }
        return nil
    }
}

private struct WindowSizeOverride: NSViewRepresentable {
    let size: CGSize?

    func makeNSView(context: Context) -> WindowSizingView {
        WindowSizingView(requestedSize: size)
    }

    func updateNSView(_ view: WindowSizingView, context: Context) {
        view.requestedSize = size
        view.applyRequestedSizeIfNeeded()
    }
}

private final class WindowSizingView: NSView {
    var requestedSize: CGSize? {
        didSet {
            if requestedSize != oldValue { hasAppliedSize = false }
        }
    }
    private var hasAppliedSize = false

    init(requestedSize: CGSize?) {
        self.requestedSize = requestedSize
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        requestedSize = nil
        super.init(coder: coder)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyRequestedSizeIfNeeded()
    }

    func applyRequestedSizeIfNeeded() {
        guard !hasAppliedSize, let requestedSize, let window else { return }
        let visibleSize = window.screen?.visibleFrame.size ?? requestedSize
        let fittedSize = CGSize(
            width: min(requestedSize.width, max(820, visibleSize.width - 20)),
            height: min(requestedSize.height, max(620, visibleSize.height - 20))
        )
        window.setContentSize(fittedSize)
        window.center()
        hasAppliedSize = true
    }
}
