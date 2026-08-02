import AppKit
import OSLog
import SwiftUI

struct LyricsDocument: Equatable, Sendable {
    let projectName: String
    let lyrics: String
    let bpm: Double?
    let musicalKey: String?
    let alternative: String
    let updatedAt: Date?
    let isHistorySnapshot: Bool
    let sections: [LyricSection]

    static func project(
        name: String,
        note: ExtractedNote,
        bpm: Double?,
        musicalKey: String?
    ) -> LyricsDocument {
        LyricsDocument(
            projectName: name,
            lyrics: note.text,
            bpm: bpm,
            musicalKey: musicalKey,
            alternative: note.alternative,
            updatedAt: nil,
            isHistorySnapshot: false,
            sections: LyricSectionParser.parse(note.text)
        )
    }

    static func history(_ entry: SongHistoryEntry) -> LyricsDocument {
        LyricsDocument(
            projectName: entry.projectName,
            lyrics: entry.sourceLyrics,
            bpm: entry.bpm,
            musicalKey: entry.musicalKey,
            alternative: entry.alternative,
            updatedAt: entry.updatedAt,
            isHistorySnapshot: true,
            sections: LyricSectionParser.parse(entry.sourceLyrics)
        )
    }
}

struct LyricsReaderView: View {
    let document: LyricsDocument
    var onOpenProject: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            readerHeader
            Divider().opacity(0.25)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock
                    if document.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        noLyricsState
                    } else {
                        lyricsCard
                        if !document.sections.isEmpty { sectionsCard }
                    }
                }
                .frame(maxWidth: 900)
                .padding(30)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Project lyrics"))
        .accessibilityIdentifier("lyrics-reader")
    }

    private var readerHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.isHistorySnapshot ? L10n.text("Saved Lyrics") : L10n.text("Project Lyrics"))
                    .font(.title3.weight(.semibold))
                Text(document.isHistorySnapshot
                     ? L10n.text("Snapshot from the last successful read")
                     : L10n.text("Read directly from Logic Project Notes"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onOpenProject {
                Button("Reopen Project", systemImage: "folder", action: onOpenProject)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("history-open-project")
            }
            if !document.lyrics.isEmpty {
                TransientCopyButton(
                    title: "Copy Lyrics",
                    copiedTitle: "Copied",
                    prominent: true,
                    accessibilityIdentifier: "lyrics-copy-all"
                ) {
                    copy(document.lyrics)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.025))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 14) {
                AccentIcon(systemName: "text.document", color: AppTheme.cyan, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.projectName)
                        .font(.title.weight(.semibold))
                        .lineLimit(2)
                    Text(sectionSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let bpm = document.bpm {
                        CapsuleStatus(
                            text: Self.formatBPM(bpm) + " BPM",
                            systemName: "metronome",
                            color: AppTheme.cyan
                        )
                    }
                    if let key = document.musicalKey {
                        CapsuleStatus(text: key, systemName: "music.note", color: AppTheme.accent)
                    }
                    if !document.alternative.isEmpty {
                        CapsuleStatus(
                            text: L10n.format("Alternative %@", document.alternative),
                            systemName: "square.stack.3d.up",
                            color: AppTheme.cyan
                        )
                    }
                    if let updatedAt = document.updatedAt {
                        CapsuleStatus(
                            text: updatedAt.formatted(date: .abbreviated, time: .shortened),
                            systemName: "clock"
                        )
                    }
                }
            }
        }
    }

    private var lyricsCard: some View {
        Text(document.lyrics)
            .font(.system(size: 16, weight: .regular))
            .lineSpacing(6)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
            .appPanel(radius: 16, padding: 24)
            .accessibilityLabel(L10n.text("Lyrics text"))
            .accessibilityIdentifier("lyrics-text")
    }

    private var sectionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Sections")
                    .font(.headline)
                Spacer()
                Text(L10n.format("%d detected", document.sections.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(Array(document.sections.enumerated()), id: \.element.id) { index, section in
                    HStack(spacing: 9) {
                        Text(String(format: "%02d", index + 1))
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(AppTheme.cyan)
                        Text(section.label)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        TransientCopyButton(
                            title: "",
                            copiedTitle: "",
                            accessibilityIdentifier: "section-copy-\(index)"
                        ) {
                            copy(section.fullText)
                        }
                    }
                    .padding(.horizontal, 11)
                    .frame(minHeight: 42)
                    .background(Color.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.055), lineWidth: 1)
                    }
                }
            }
        }
        .appPanel(radius: 16, padding: 18)
    }

    private var noLyricsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.document")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppTheme.cyan)
                .accessibilityHidden(true)
            Text("No Project Notes Found")
                .font(.title3.weight(.semibold))
            Text("This Logic alternative does not currently contain readable Project Notes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .appPanel(radius: 16, padding: 24)
    }

    private var sectionSummary: String {
        if document.sections.isEmpty { return L10n.text("No section markers detected") }
        return L10n.format("%d sections detected", document.sections.count)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        AppLog.ui.debug("Lyrics copied to pasteboard characters=\(text.count, privacy: .public)")
    }

    private static func formatBPM(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}

private struct TransientCopyButton: View {
    let title: String
    let copiedTitle: String
    var prominent = false
    let accessibilityIdentifier: String
    let action: () -> Void
    @State private var isCopied = false

    @ViewBuilder
    var body: some View {
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button {
            action()
            isCopied = true
        } label: {
            if title.isEmpty {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .frame(width: 20, height: 20)
            } else {
                Label(isCopied ? copiedTitle : title, systemImage: isCopied ? "checkmark" : "doc.on.doc")
            }
        }
        .controlSize(title.isEmpty ? .small : .large)
        .help(L10n.text("Copy to clipboard"))
        .accessibilityLabel(isCopied ? L10n.text("Copied") : L10n.text("Copy"))
        .accessibilityIdentifier(accessibilityIdentifier)
        .task(id: isCopied) {
            guard isCopied else { return }
            try? await Task<Never, Never>.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            isCopied = false
        }
    }
}
