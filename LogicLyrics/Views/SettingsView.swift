import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var updater: UpdateService
    @AppStorage(UpdatePreferences.automaticallyChecksForUpdatesKey)
    private var automaticallyChecksForUpdates = true
    @State private var confirmsUpdateInstallation = false

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                Text("Checks silently when Logic Lyrics opens. Updates are never installed without your confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Check Now") { updater.check(silent: false) }
                        .disabled(updater.state == .checking)
                    updateCheckResult
                }
                if case .available = updater.state {
                    Button("Install Update") { confirmsUpdateInstallation = true }
                        .buttonStyle(.borderedProminent)
                }
            }

            Section("Privacy & Diagnostics") {
                LabeledContent("Project processing", value: "Entirely on this Mac")
                LabeledContent("Project modification", value: "Never")
                Button("Copy System Diagnostics") { AppDiagnostics.copyToPasteboard() }
                Text("Diagnostics contain app and system information plus privacy-safe Logic Lyrics events. Lyrics and file paths are never logged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 420)
        .alert("Logic Lyrics", isPresented: Binding(
            get: { updater.errorMessage != nil },
            set: { if !$0 { updater.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { updater.errorMessage = nil }
        } message: {
            Text(updater.errorMessage ?? "")
        }
        .confirmationDialog(
            L10n.format("Install Logic Lyrics %@?", availableUpdateVersion ?? ""),
            isPresented: $confirmsUpdateInstallation,
            titleVisibility: .visible
        ) {
            Button("Not Now", role: .cancel) {}
            Button("Install Update") { updater.installAvailableUpdate() }
        } message: {
            Text("Logic Lyrics will close, rebuild the verified update, preserve a backup, and reopen automatically.")
        }
    }

    @ViewBuilder
    private var updateCheckResult: some View {
        switch updater.state {
        case .idle:
            Text("No update check has been run.").foregroundStyle(.secondary)
        case .checking:
            ProgressView().controlSize(.small)
                .accessibilityLabel(L10n.text("Checking for updates"))
            Text("Checking for updates…").foregroundStyle(.secondary)
        case .current:
            Label("Logic Lyrics is up to date.", systemImage: "checkmark.circle.fill")
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
