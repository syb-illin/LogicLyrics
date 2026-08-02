import SwiftUI

struct RecentProjectsView: View {
    @ObservedObject var history: HistoryStore
    let selectedID: UUID?
    let onSelect: (UUID) -> Void
    let onTogglePin: (UUID) -> Void
    let onOpenInLogic: (UUID) -> Void
    let onRevealInFinder: (UUID) -> Void
    let onRemove: (UUID) -> Void
    let onRemoveMissing: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("RECENT PROJECTS"))
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text(resultCountAccessibilityLabel)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier("recent-songs-count")
                Menu {
                    Button(L10n.text("Remove Missing Projects"), systemImage: "folder.badge.minus") {
                        onRemoveMissing()
                    }
                    .disabled(history.entries.isEmpty)
                    Button(L10n.text("Clear History"), systemImage: "trash", role: .destructive) {
                        onClear()
                    }
                    .disabled(history.entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(L10n.text("History Actions"))
                .accessibilityIdentifier("history-management-menu")
            }
            .padding(.horizontal, 8)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityHidden(true)
                TextField(L10n.text("Search"), text: $history.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel(L10n.text("Search recent songs"))
                    .accessibilityIdentifier("history-search-field")
            }
            .padding(10)
            .background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Toggle(L10n.text("No lyrics"), isOn: $history.showsOnlyProjectsWithoutLyrics)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.caption)
                .padding(.horizontal, 8)
                .accessibilityHint(L10n.text("Shows only Logic projects whose Project Notes are empty."))
                .accessibilityIdentifier("missing-lyrics-filter")

            if history.filteredEntries.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22))
                        .foregroundStyle(AppTheme.secondaryText)
                        .accessibilityHidden(true)
                    Text(history.entries.isEmpty
                         ? L10n.text("No recent projects")
                         : L10n.text("No matching projects"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(history.filteredEntries) { entry in
                        HStack(spacing: 2) {
                            Button { onSelect(entry.id) } label: {
                            HStack(spacing: 10) {
                                AccentIcon(systemName: "music.note", color: AppTheme.cyan, size: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.projectName)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(metadata(for: entry))
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if entry.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.cyan)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(9)
                            .background(
                                selectedID == entry.id ? AppTheme.cyan.opacity(0.13) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .contentShape(Rectangle())
                        }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                L10n.format("%@: %@", entry.projectName, metadata(for: entry))
                            )
                            .accessibilityHint(L10n.text("Shows the lyrics saved from this Logic project."))
                            .accessibilityIdentifier("history-row-\(entry.id.uuidString.lowercased())")
                            .contextMenu { entryActions(entry) }

                            Menu { entryActions(entry) } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 24, height: 30)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .accessibilityLabel(L10n.format("Actions for %@", entry.projectName))
                            .accessibilityIdentifier("history-actions-\(entry.id.uuidString.lowercased())")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Recent songs"))
        .accessibilityIdentifier("recent-songs-section")
    }

    @ViewBuilder
    private func entryActions(_ entry: SongHistoryEntry) -> some View {
        Button(
            entry.isPinned ? L10n.text("Unpin") : L10n.text("Pin"),
            systemImage: entry.isPinned ? "pin.slash" : "pin"
        ) { onTogglePin(entry.id) }
        Divider()
        Button(L10n.text("Open in Logic Pro"), systemImage: "music.note") {
            onOpenInLogic(entry.id)
        }
        Button(L10n.text("Reveal in Finder"), systemImage: "finder") {
            onRevealInFinder(entry.id)
        }
        Divider()
        Button(L10n.text("Remove from History"), systemImage: "trash", role: .destructive) {
            onRemove(entry.id)
        }
    }

    private func metadata(for entry: SongHistoryEntry) -> String {
        [
            entry.bpm.map { Self.formatBPM($0) + " BPM" },
            entry.musicalKey,
            entry.updatedAt.formatted(date: .abbreviated, time: .omitted)
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var resultCountAccessibilityLabel: String {
        history.filteredEntries.count == 1
            ? L10n.text("1 song")
            : L10n.format("%d songs", history.filteredEntries.count)
    }

    private static func formatBPM(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}
