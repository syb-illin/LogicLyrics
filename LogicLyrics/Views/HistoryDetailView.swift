import AppKit
import SwiftUI

struct HistoryDetailView: View {
    let entry: SongHistoryEntry
    let onDelete: () -> Void
    @State private var copied = ""
    @State private var confirmsDeletion = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                historyCard("Paroles", icon: "text.quote", color: AppTheme.cyan, value: entry.lyrics, field: "lyrics")
                if !entry.prompt.isEmpty {
                    historyCard("Prompt Suno", icon: "sparkles", color: AppTheme.accent, value: entry.prompt, field: "prompt")
                } else {
                    Label("Aucun prompt généré pour ce morceau", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .appPanel()
                }
            }
            .frame(maxWidth: 860)
            .padding(30)
            .frame(maxWidth: .infinity)
        }
        .alert("Supprimer ce morceau de l’historique ?", isPresented: $confirmsDeletion) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive, action: onDelete)
        } message: {
            Text("Les paroles et le prompt sauvegardés pour « \(entry.projectName) » seront supprimés. Le projet Logic ne sera pas modifié.")
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 15) {
            AccentIcon(systemName: "clock.arrow.circlepath", color: AppTheme.cyan, size: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.projectName)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(entry.projectPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    CapsuleStatus(text: entry.updatedAt.formatted(date: .abbreviated, time: .shortened), systemName: "clock")
                    if let bpm = entry.bpm {
                        CapsuleStatus(text: Self.formatBPM(bpm) + " BPM", systemName: "metronome", color: AppTheme.cyan)
                    }
                    if let key = entry.musicalKey {
                        CapsuleStatus(text: key, systemName: "music.quarternote.3", color: AppTheme.accent)
                    }
                    if !entry.alternative.isEmpty {
                        CapsuleStatus(text: "Alternative \(entry.alternative)", systemName: "square.stack.3d.up", color: AppTheme.cyan)
                    }
                    if !entry.referenceArtist.isEmpty {
                        CapsuleStatus(text: entry.referenceArtist, systemName: "music.note", color: AppTheme.accent)
                    }
                }
            }
            Spacer()
            Button(role: .destructive) { confirmsDeletion = true } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    private func historyCard(_ title: String, icon: String, color: Color, value: String, field: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AccentIcon(systemName: icon, color: color, size: 36)
                Text(title).font(.headline)
                Spacer()
                Button(copied == field ? "Copié" : "Copier", systemImage: copied == field ? "checkmark" : "doc.on.doc") {
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
        }
        .appPanel(radius: 20, padding: 20)
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
