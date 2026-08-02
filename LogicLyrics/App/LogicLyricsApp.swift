import AppKit
import SwiftUI

@main
@MainActor
struct LogicLyricsApp: App {
    @StateObject private var updater = UpdateService()
    @Environment(\.openWindow) private var openWindow

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let localization = Bundle.main.preferredLocalizations.first ?? "unknown"
        AppLog.lifecycle.notice("Application launched version=\(version, privacy: .public) build=\(build, privacy: .public) localization=\(localization, privacy: .public)")
    }

    var body: some Scene {
        WindowGroup(L10n.text("Logic Lyrics"), id: "main") {
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
            LogicProjectCommands()
            CommandGroup(replacing: .appInfo) {
                Button(L10n.text("About Logic Lyrics")) {
                    openWindow(id: "about")
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .accessibilityIdentifier("about-menu-item")
            }
            CommandMenu(L10n.text("Diagnostics")) {
                Button(L10n.text("Copy System Diagnostics")) {
                    AppDiagnostics.copyToPasteboard()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
                .accessibilityIdentifier("diagnostics-copy-menu-item")
            }
        }

        Settings {
            AppSettingsView()
                .environmentObject(updater)
        }

        Window(L10n.text("About Logic Lyrics"), id: "about") {
            AboutView(versionLabel: Self.versionLabel)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 440, height: 360)
        .windowResizability(.contentSize)
    }

    private static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return L10n.format("%@ (build %@)", version, build)
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

private struct AboutView: View {
    let versionLabel: String

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(L10n.text("Logic Lyrics"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(versionLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
            }

            Text(L10n.text("Reads tempo, key and lyrics directly from Logic Pro Project Notes without modifying your project."))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
        }
        .padding(32)
        .frame(width: 440, minHeight: 330)
        .background(Color(red: 0.055, green: 0.055, blue: 0.09))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("About Logic Lyrics"))
        .accessibilityIdentifier("about-view")
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
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        requestedSize = nil
        super.init(coder: coder)
        setAccessibilityElement(false)
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
