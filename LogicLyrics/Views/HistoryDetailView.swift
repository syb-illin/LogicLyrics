import AppKit
import SwiftUI

struct HistoryDetailView: View {
    let entry: SongHistoryEntry
    let onOpenProject: () -> Void
    let onLocateProject: () -> Void
    let onRevertToSource: () -> Void
    let onRestoreRevision: (String) -> Void
    let onDelete: () -> Void
    @State private var copied = ""
    @State private var confirmsDeletion = false
    @State private var recoveredRevisionsExpanded = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                historyCard(
                    "Project Lyrics", icon: "text.quote", color: AppTheme.cyan,
                    value: entry.sourceLyrics, field: "source-lyrics"
                )
                if let edited = entry.editedLyrics {
                    historyCard(
                        "Edited Lyrics", icon: "pencil.and.outline", color: AppTheme.accent,
                        value: edited, field: "edited-lyrics"
                    )
                }
                if !entry.prompt.isEmpty {
                    historyCard("Suno Prompt", icon: "sparkles", color: AppTheme.accent, value: entry.prompt, field: "prompt")
                } else {
                    Label("No prompt has been generated for this song", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .appPanel()
                }
                if !entry.recoveredLyrics.isEmpty { recoveredLyricsCard }
            }
            .frame(maxWidth: 860)
            .padding(30)
            .frame(maxWidth: .infinity)
        }
        .alert("Delete this song from history?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text(L10n.format("The saved lyrics and prompt for “%@” will be deleted. The Logic project will not be modified.", entry.projectName))
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
        }
        .accessibilityLabel(L10n.text("Song history details"))
        .accessibilityIdentifier("history-detail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 15) {
                AccentIcon(systemName: "clock.arrow.circlepath", color: AppTheme.cyan, size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.projectName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(entry.projectPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 9) {
                Button("Open Project", systemImage: "folder") { onOpenProject() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("history-open-project")
                Button("Locate Project…", systemImage: "scope") { onLocateProject() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("history-locate-project")
                if entry.hasLocalEdits {
                    Button("Revert to Project Lyrics", systemImage: "arrow.uturn.backward") {
                        onRevertToSource()
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.text("Keep the edit as a recoverable revision and show the latest lyrics extracted from Logic."))
                    .accessibilityIdentifier("history-revert-edit")
                }
                Spacer()
                Button(role: .destructive) { confirmsDeletion = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("history-delete")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CapsuleStatus(text: entry.updatedAt.formatted(date: .abbreviated, time: .shortened), systemName: "clock")
                    if let bpm = entry.bpm {
                        CapsuleStatus(text: Self.formatBPM(bpm) + " BPM", systemName: "metronome", color: AppTheme.cyan)
                    }
                    if let key = entry.musicalKey {
                        CapsuleStatus(text: key, systemName: "music.quarternote.3", color: AppTheme.accent)
                    }
                    if !entry.alternative.isEmpty {
                        CapsuleStatus(text: L10n.format("Alternative %@", entry.alternative), systemName: "square.stack.3d.up", color: AppTheme.cyan)
                    }
                    if !entry.referenceArtist.isEmpty {
                        CapsuleStatus(text: entry.referenceArtist, systemName: "music.note", color: AppTheme.accent)
                    }
                    if entry.hasLocalEdits {
                        CapsuleStatus(text: L10n.text("Edited"), systemName: "pencil", color: AppTheme.accent)
                    }
                }
            }
        }
    }

    private var recoveredLyricsCard: some View {
        DisclosureGroup(isExpanded: $recoveredRevisionsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Older values were preserved during history migration. They may include previous edits or technical text detected by older versions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(entry.recoveredLyrics.enumerated()), id: \.offset) { index, value in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.format("Recovered text %d", index + 1))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button(
                                copied == "recovered-\(index)" ? L10n.text("Copied") : L10n.text("Copy"),
                                systemImage: copied == "recovered-\(index)" ? "checkmark" : "doc.on.doc"
                            ) {
                                copy(value, field: "recovered-\(index)")
                            }
                            .buttonStyle(.bordered)
                            Button("Restore", systemImage: "arrow.counterclockwise") {
                                onRestoreRevision(value)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel(L10n.format("Restore recovered text %d", index + 1))
                            .accessibilityIdentifier("history-restore-revision-\(index)")
                        }
                        Text(value)
                            .font(.system(size: 13, design: .rounded))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.top, 12)
        } label: {
            Label(
                L10n.format("Recovered Legacy Text (%d)", entry.recoveredLyrics.count),
                systemImage: "archivebox"
            )
            .font(.headline)
        }
        .appPanel(radius: 20, padding: 20)
        .accessibilityLabel(L10n.format("Recovered Legacy Text (%d)", entry.recoveredLyrics.count))
        .accessibilityIdentifier("history-recovered-revisions")
    }

    private func historyCard(_ title: String, icon: String, color: Color, value: String, field: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AccentIcon(systemName: icon, color: color, size: 36)
                Text(L10n.text(title))
                    .font(.headline)
                Spacer()
                Button(copied == field ? L10n.text("Copied") : L10n.text("Copy"), systemImage: copied == field ? "checkmark" : "doc.on.doc") {
                    copy(value, field: field)
                }
                .buttonStyle(.bordered)
            }
            Text(value)
                .font(.system(size: 14, design: .rounded))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .background(Color.black.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(L10n.format("%@ content", L10n.text(title)))
        }
        .appPanel(radius: 20, padding: 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(title))
        .accessibilityIdentifier("history-\(field)")
    }

    private func copy(_ text: String, field: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = field
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task<Never, Never>.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            if copied == field { copied = "" }
        }
    }

    private static func formatBPM(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}
