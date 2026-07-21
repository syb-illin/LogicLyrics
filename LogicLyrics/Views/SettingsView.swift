import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var updater: UpdateService
    @AppStorage(UpdatePreferences.automaticallyChecksForUpdatesKey)
    private var automaticallyChecksForUpdates = true
    @AppStorage("metadata.defaultArtist") private var defaultArtist = "wake up fall"
    @AppStorage("metadata.filenameTemplate") private var filenameTemplate = "{track} {group} - {title} {year}"
    @AppStorage("metadata.mp3Mode") private var mp3Mode = MP3EncodingMode.cbr.rawValue
    @AppStorage("metadata.mp3Bitrate") private var mp3Bitrate = MP3Bitrate.kbps320.rawValue
    @AppStorage("metadata.mp3VBRQuality") private var mp3VBRQuality = MP3VBRQuality.v0.rawValue
    @AppStorage("metadata.mp3SampleRate") private var mp3SampleRate = MP3SampleRate.source.rawValue
    @State private var confirmsUpdateInstallation = false

    var body: some View {
        Form {
            updateSection
            metadataSection
            conversionSection
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560, height: 640)
        .onAppear(perform: migrateLegacyEncodingSettings)
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

    private var updateSection: some View {
        Section("Updates") {
            Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
            Text("Checks silently when Logic Lyrics opens. Manual checks remain available.")
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
            Text("Updates are never installed without your confirmation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var metadataSection: some View {
        Section("Audio Metadata") {
            TextField("Default artist", text: $defaultArtist)
            TextField("Filename format", text: $filenameTemplate)
            Text("Tokens: {track} {group} {title} {album} {year} {bpm}")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Default year", value: String(Calendar.current.component(.year, from: Date())))
            Text("The year automatically follows the current calendar year.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var conversionSection: some View {
        Section("WAV to MP3 Conversion") {
            Picker("Mode", selection: $mp3Mode) {
                ForEach(MP3EncodingMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            if mp3Mode == MP3EncodingMode.cbr.rawValue {
                Picker("Bitrate", selection: $mp3Bitrate) {
                    ForEach(MP3Bitrate.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } else {
                Picker("VBR Quality", selection: $mp3VBRQuality) {
                    ForEach(MP3VBRQuality.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Picker("Sample Rate", selection: $mp3SampleRate) {
                ForEach(MP3SampleRate.allCases) { Text($0.label).tag($0.rawValue) }
            }
            LabeledContent(L10n.text("Channels"), value: L10n.text("Joint stereo"))
            LabeledContent(L10n.text("Encoding quality"), value: L10n.text("Maximum"))
        }
    }

    @ViewBuilder
    private var updateCheckResult: some View {
        switch updater.state {
        case .idle:
            Text("No update check has been run.")
                .foregroundStyle(.secondary)
        case .checking:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(L10n.text("Checking for updates"))
            Text("Checking for updates…")
                .foregroundStyle(.secondary)
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

    private func migrateLegacyEncodingSettings() {
        if MP3EncodingMode(rawValue: mp3Mode) == nil { mp3Mode = MP3EncodingMode.cbr.rawValue }
        if MP3Bitrate(rawValue: mp3Bitrate) == nil { mp3Bitrate = MP3Bitrate.kbps320.rawValue }
        if MP3VBRQuality(rawValue: mp3VBRQuality) == nil { mp3VBRQuality = MP3VBRQuality.v0.rawValue }
        if MP3SampleRate(rawValue: mp3SampleRate) == nil { mp3SampleRate = MP3SampleRate.source.rawValue }
    }
}
