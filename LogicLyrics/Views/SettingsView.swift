import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var updater: UpdateService
    @AppStorage(UpdatePreferences.automaticallyChecksForUpdatesKey)
    private var automaticallyChecksForUpdates = true
    @State private var confirmsUpdateInstallation = false

    var body: some View {
        Form {
            Section(L10n.text("Updates")) {
                Toggle(L10n.text("Automatically check for updates"), isOn: $automaticallyChecksForUpdates)
                Text(L10n.text("Checks silently when Logic Lyrics opens. Updates are never installed without your confirmation."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(L10n.text("Check Now")) { updater.check(silent: false) }
                        .disabled(updater.state == .checking)
                    updateCheckResult
                }
                if case .available = updater.state {
                    Button(L10n.text("Install Update")) { confirmsUpdateInstallation = true }
                        .buttonStyle(.borderedProminent)
                }
            }

            Section(L10n.text("Privacy & Diagnostics")) {
                LabeledContent(
                    L10n.text("Project processing"),
                    value: L10n.text("Entirely on this Mac")
                )
                LabeledContent(
                    L10n.text("Project modification"),
                    value: L10n.text("Never")
                )
                Button(L10n.text("Copy System Diagnostics")) { AppDiagnostics.copyToPasteboard() }
                Text(L10n.text("Diagnostics contain app and system information plus privacy-safe Logic Lyrics events. Lyrics and file paths are never logged."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 420)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Logic Lyrics settings"))
        .accessibilityIdentifier("settings-view")
        .alert(L10n.text("Logic Lyrics"), isPresented: Binding(
            get: { updater.errorMessage != nil },
            set: { if !$0 { updater.errorMessage = nil } }
        )) {
            Button(L10n.text("OK"), role: .cancel) { updater.errorMessage = nil }
        } message: {
            Text(updater.errorMessage ?? "")
        }
        .confirmationDialog(
            L10n.format("Install Logic Lyrics %@?", availableUpdateVersion ?? ""),
            isPresented: $confirmsUpdateInstallation,
            titleVisibility: .visible
        ) {
            Button(L10n.text("Not Now"), role: .cancel) {}
            Button(L10n.text("Install Update")) { updater.installAvailableUpdate() }
        } message: {
            Text(L10n.text("Logic Lyrics will close, rebuild the verified update, preserve a backup, and reopen automatically."))
        }
    }

    @ViewBuilder
    private var updateCheckResult: some View {
        switch updater.state {
        case .idle:
            Text(L10n.text("No update check has been run.")).foregroundStyle(.secondary)
        case .checking:
            ProgressView().controlSize(.small)
                .accessibilityLabel(L10n.text("Checking for updates"))
            Text(L10n.text("Checking for updates…")).foregroundStyle(.secondary)
        case .current:
            Label(L10n.text("Logic Lyrics is up to date."), systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.green)
        case .available(let version):
            Label(L10n.format("Version %@ is available.", version), systemImage: "arrow.down.circle.fill")
                .foregroundStyle(AppTheme.cyan)
        }
    }

    private var availableUpdateVersion: String? {
        if case .available(let version) = updater.state { return version }
        return nil
    }
}
