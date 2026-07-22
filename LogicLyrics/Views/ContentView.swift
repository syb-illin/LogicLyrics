import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

private enum WorkspaceMode: Int {
    case lyrics
    case suno
    case metadata
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(UpdatePreferences.automaticallyChecksForUpdatesKey)
    private var automaticallyChecksForUpdates = true
    @StateObject private var model = ProjectViewModel()
    @StateObject private var history: HistoryStore
    @EnvironmentObject private var updater: UpdateService
    @State private var isTargeted = false
    @State private var showImporter = false
    @State private var showAudioImporter = false
    @State private var selectedMode = WorkspaceMode.lyrics
    @State private var showsHistory = false
    @State private var currentHistoryID: UUID?
    @State private var historyIDsByNote = [String: UUID]()
    @State private var selectedHistoryID: UUID?
    @State private var pendingAudioURL: URL?
    @State private var historySaveTask: Task<Void, Never>?
    @State private var hasPendingHistoryLyricsSave = false
    @State private var confirmsLogicWrite = false
    @State private var confirmsUpdateInstallation = false

    private let logicProjectType = UTType(filenameExtension: "logicx") ?? UTType.package
    private let historyArchiveType = UTType(
        filenameExtension: HistoryArchiveService.fileExtension,
        conformingTo: .json
    ) ?? .json

    init() {
        _history = StateObject(wrappedValue: HistoryStore.configuredForCurrentProcess())
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 245, ideal: 285, max: 350)
            } detail: {
                workspace
            }
            .navigationSplitViewStyle(.balanced)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Logic Lyrics workspace"))
        .accessibilityIdentifier("logic-lyrics-workspace")
        .tint(AppTheme.accent)
        .navigationTitle(model.projectName.isEmpty ? "Logic Lyrics" : model.projectName)
        .toolbar { toolbar }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: receiveDrop)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [logicProjectType, UTType.package],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { openLogicProject(url) }
            case .failure(let error):
                model.errorMessage = String(format: String(localized: "Unable to open the project: %@"), error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [UTType.mp3, UTType.wav],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { openAudio(url) }
            case .failure(let error):
                model.errorMessage = String(format: String(localized: "Unable to open the audio file: %@"), error.localizedDescription)
            }
        }
        .alert(currentAlertTitle, isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(currentErrorMessage)
        }
        .alert(model.selectedNote?.isDraft == true ? L10n.text("Add these lyrics to a Logic copy?") : L10n.text("Create an experimental Logic copy?"), isPresented: $confirmsLogicWrite) {
            Button("Cancel", role: .cancel) {}
            Button("Create Copy") { model.createEditedProjectCopy() }
        } message: {
            Text("The original will never be modified. The app recognizes and updates the terminal Notes structure, then reads the copy back. Final compatibility must be confirmed by opening it in Logic Pro.")
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
        .onAppear {
            if automaticallyChecksForUpdates && !Self.isUITesting {
                updater.check(silent: true)
            } else {
                AppLog.updates.info("Automatic update check skipped because it is disabled")
            }
            model.onProjectLoaded = { name, url, notes, bpm, musicalKey in
                historySaveTask?.cancel()
                historySaveTask = nil
                hasPendingHistoryLyricsSave = false
                var identifiers = [String: UUID]()
                for note in notes {
                    let identifier = history.recordProject(
                        name: name, url: url, noteKey: note.id, alternative: note.alternative,
                        lyrics: note.text, bpm: bpm, musicalKey: musicalKey
                    )
                    identifiers[note.id] = identifier
                }
                historyIDsByNote = identifiers
                currentHistoryID = notes.first.flatMap { identifiers[$0.id] }
                selectedHistoryID = nil
                showsHistory = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                flushHistorySave()
                history.flush()
            }
        }
        .overlay { ProcessingOverlay(state: activeOperationState, cancel: cancelActiveOperation) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader
            Divider().opacity(0.35)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if model.notes.isEmpty {
                        compactEmptyState
                            .frame(minHeight: 250)
                    } else {
                        projectCard
                        notePicker
                        if !model.sections.isEmpty { sectionPicker }
                    }
                    Divider().opacity(0.3)
                    recentSongsSection
                }
                .padding(14)
            }
        }
        .background {
            if reduceTransparency {
                Color(red: 0.06, green: 0.06, blue: 0.10)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .overlay(alignment: .trailing) { Divider().opacity(0.25) }
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            AccentIcon(systemName: "waveform.and.mic", size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Logic Lyrics")
                    .font(.headline)
                    .accessibilityIdentifier("logic-lyrics-root")
                Text("Project Notes Studio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("v\(Self.appVersion) · build \(Self.buildNumber)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                if selectedMode == .metadata { showAudioImporter = true } else { showImporter = true }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(selectedMode == .metadata ? L10n.text("Open an MP3 or WAV file") : L10n.text("Open a Logic Pro project"))
            .accessibilityLabel(selectedMode == .metadata ? L10n.text("Open audio file") : L10n.text("Open Logic project"))
            .accessibilityHint(L10n.text("Opens a file picker. Drag and drop remains available as an alternative."))
            Button {
                flushHistorySave()
                if showsHistory {
                    showsHistory = false
                } else {
                    selectedHistoryID = currentHistoryID ?? history.entries.first?.id
                    showsHistory = selectedHistoryID != nil
                }
            } label: {
                Image(systemName: showsHistory ? "clock.fill" : "clock")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(showsHistory ? AppTheme.cyan.opacity(0.18) : Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.text("Song history"))
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .accessibilityLabel(showsHistory ? L10n.text("Hide song history") : L10n.text("Show song history"))
            .accessibilityHint(L10n.text("Shows locally saved songs, lyrics, and prompts."))
        }
        .padding(16)
    }

    private var compactEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppTheme.cyan)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(selectedMode == .metadata ? L10n.text("Drop a Suno Export") : L10n.text("Drop a Project")).font(.headline)
                Text(selectedMode == .metadata
                     ? L10n.text("Drop an MP3 or WAV file\nto read and write its metadata")
                     : L10n.text("Drop a .logicx file\nto extract its lyrics"))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button(selectedMode == .metadata ? L10n.text("Choose MP3/WAV") : L10n.text("Choose a Project")) {
                if selectedMode == .metadata { showAudioImporter = true } else { showImporter = true }
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            selectedMode == .metadata
                ? L10n.text("Audio file import")
                : L10n.text("Logic project import")
        )
    }

    private var recentSongsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sidebarTitle("RECENT SONGS")
                Spacer()
                Text("\(history.entries.count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.format("%d songs", history.entries.count))
                Menu {
                    Button("Export History…", systemImage: "square.and.arrow.up") {
                        exportHistory()
                    }
                    .disabled(history.entries.isEmpty)
                    Button("Import History…", systemImage: "square.and.arrow.down") {
                        importHistory()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.text("Import or export song history"))
                .accessibilityLabel(L10n.text("History transfer actions"))
                .accessibilityHint(L10n.text("Import or export song history"))
                .accessibilityValue(L10n.text("Import or export song history"))
                .accessibilityIdentifier("history-transfer-menu")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search", text: $history.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel(L10n.text("Search recent songs"))
                    .accessibilityIdentifier("history-search-field")
            }
            .padding(10)
            .background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if history.filteredEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 24)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(history.entries.isEmpty ? L10n.text("No songs in history") : L10n.text("No matching songs"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(history.filteredEntries) { entry in
                        Button {
                            flushHistorySave()
                            selectedHistoryID = entry.id
                            showsHistory = true
                        } label: {
                            HStack(spacing: 10) {
                                AccentIcon(systemName: "music.note", color: AppTheme.cyan, size: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.projectName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text([
                                        entry.bpm.map { Self.formatBPM($0) + " BPM" },
                                        entry.musicalKey,
                                        entry.updatedAt.formatted(date: .abbreviated, time: .omitted)
                                    ].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if entry.hasLocalEdits {
                                    Image(systemName: "pencil")
                                        .font(.caption2).foregroundStyle(AppTheme.cyan)
                                        .accessibilityLabel(L10n.text("Edited lyrics"))
                                }
                                if !entry.prompt.isEmpty {
                                    Image(systemName: "sparkles")
                                        .font(.caption).foregroundStyle(AppTheme.accent)
                                        .accessibilityLabel(L10n.text("Saved Suno prompt"))
                                }
                            }
                            .padding(9)
                            .background(
                                showsHistory && selectedHistoryID == entry.id
                                    ? AppTheme.cyan.opacity(0.13) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(L10n.text("Shows the saved project lyrics and Suno prompt."))
                        .accessibilityIdentifier("history-row-\(entry.id.uuidString.lowercased())")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Recent songs"))
        .accessibilityIdentifier("recent-songs-section")
    }

    private var projectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                AccentIcon(systemName: "music.note", color: AppTheme.cyan, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.projectName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(L10n.format("%d sections detected", model.sections.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                CapsuleStatus(text: "Logic", systemName: "checkmark")
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 8) {
                projectMetadata(
                    title: "TEMPO",
                    value: model.bpm.map { Self.formatBPM($0) + " BPM" } ?? String(localized: "Not detected"),
                    systemName: "metronome",
                    color: AppTheme.cyan
                )
                projectMetadata(
                    title: String(localized: "KEY"),
                    value: model.musicalKey ?? String(localized: "Not detected"),
                    systemName: "music.note",
                    color: AppTheme.accent
                )
            }
        }
        .appPanel(radius: 15, padding: 13)
    }

    private func projectMetadata(title: String, value: String, systemName: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.text(title))
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("%@: %@", title, value))
    }

    private var notePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarTitle(String(localized: "PROJECT NOTES"))
            ForEach(model.notes) { note in
                Button {
                    flushHistorySave()
                    model.selectedNoteID = note.id
                    currentHistoryID = historyIDsByNote[note.id]
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.selectedNoteID == note.id ? "doc.text.fill" : "doc.text")
                            .foregroundStyle(model.selectedNoteID == note.id ? AppTheme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).lineLimit(1)
                            Text(L10n.format("Alternative %@", note.alternative))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(model.selectedNoteID == note.id ? AppTheme.accent.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sectionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarTitle("STRUCTURE")
            ForEach(model.sections.indices, id: \.self) { index in
                let section = model.sections[index]
                HStack(spacing: 9) {
                    Text(String(format: "%02d", index + 1))
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(AppTheme.cyan)
                        .frame(width: 23)
                    Text(section.label).font(.subheadline).lineLimit(1)
                    Spacer()
                    Button { model.copySection(section) } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("Copy this section"))
                    .accessibilityLabel(L10n.format("Copy %@ section", section.label))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }

    private func sidebarTitle(_ value: String) -> some View {
        Text(L10n.text(value))
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider().opacity(0.25)
            Group {
                if showsHistory, let entry = history.entry(id: selectedHistoryID) {
                    HistoryDetailView(
                        entry: entry,
                        onOpenProject: { reopenHistoryProject(entry.id) },
                        onLocateProject: { locateHistoryProject(entry.id) },
                        onRevertToSource: { revertHistoryEntry(entry) },
                        onRestoreRevision: { restoreHistoryRevision(entryID: entry.id, lyrics: $0) },
                        onDelete: {
                            history.delete(id: entry.id)
                            if currentHistoryID == entry.id {
                                currentHistoryID = nil
                                historyIDsByNote = historyIDsByNote.filter { $0.value != entry.id }
                            }
                            selectedHistoryID = history.entries.first?.id
                        }
                    )
                } else if showsHistory {
                    historyEmptyState
                } else if model.isLoading {
                    loadingState
                } else if selectedMode == .metadata {
                    AudioMetadataView(
                        projectName: model.projectName,
                        suggestedTitle: model.suggestedSongTitle,
                        bpm: model.bpm,
                        lyrics: model.selectedNote?.text ?? "",
                        audioURL: pendingAudioURL
                    )
                    .id(currentHistoryID)
                } else if model.selectedNote == nil {
                    heroDropZone
                } else if selectedMode == .lyrics {
                    lyricsReader
                } else if selectedMode == .suno {
                    let saved = history.entry(id: currentHistoryID)
                    SunoGeneratorView(
                        lyrics: model.selectedNote?.text ?? "",
                        detectedBPM: model.bpm,
                        detectedKey: model.musicalKey,
                        initialPrompt: saved?.prompt ?? "",
                        initialReferenceArtist: saved?.referenceArtist ?? "",
                        initialAllowsFemaleBackingVocals: saved?.allowsFemaleBackingVocals ?? false
                    ) { prompt, artist, allowsFemale in
                        guard let currentHistoryID else { return }
                        history.savePrompt(
                            entryID: currentHistoryID,
                            prompt: prompt,
                            referenceArtist: artist,
                            allowsFemaleBackingVocals: allowsFemale
                        )
                    }
                    .id(currentHistoryID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(showsHistory ? L10n.text("Song history details") : workspaceTitle)
        }
        .background(Color.black.opacity(0.08))
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppTheme.cyan, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                    .background(AppTheme.cyan.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
    }

    private static func formatBPM(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    private var workspaceHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(showsHistory ? L10n.text("History") : workspaceTitle)
                    .font(.title3.weight(.semibold))
                Text(showsHistory
                     ? L10n.text("Songs, lyrics, and prompts saved on this Mac")
                     : workspaceSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsHistory {
                Button("Back to Project", systemImage: "arrow.left") { showsHistory = false }
                    .buttonStyle(.bordered)
            } else {
                Picker("View", selection: $selectedMode) {
                    Label("Lyrics", systemImage: "text.alignleft").tag(WorkspaceMode.lyrics)
                    Label("Suno AI", systemImage: "sparkles").tag(WorkspaceMode.suno)
                    Label("Audio Tags", systemImage: "tag.fill").tag(WorkspaceMode.metadata)
                }
                .pickerStyle(.segmented)
                .frame(width: 390)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background {
            if reduceTransparency {
                Color(red: 0.07, green: 0.07, blue: 0.11)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    private var workspaceTitle: String {
        switch selectedMode {
        case .lyrics: String(localized: "Lyrics")
        case .suno: L10n.text("Suno Studio")
        case .metadata: String(localized: "Audio Metadata")
        }
    }

    private var workspaceSubtitle: String {
        switch selectedMode {
        case .lyrics: String(localized: "Notes extracted from the Logic project")
        case .suno: String(localized: "Prepare a voice-faithful prompt")
        case .metadata: String(localized: "Tag Suno MP3 and WAV exports")
        }
    }

    private var lyricsReader: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.selectedNote?.title ?? String(localized: "Lyrics"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(L10n.format("%d sections • automatic editing and saving", model.sections.count))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.selectedNote?.isDraft == true ? L10n.text("Add to a Logic Copy") : L10n.text("Logic Copy"), systemImage: "doc.on.doc.fill") {
                        flushHistorySave()
                        confirmsLogicWrite = true
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.text("Create a .logicx copy containing these lyrics without changing the original"))
                    .disabled(model.selectedNote?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                    Button(model.didCopy ? L10n.text("Copied") : L10n.text("Copy All"), systemImage: model.didCopy ? "checkmark" : "doc.on.doc") {
                        model.copySelectedNote()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if let message = model.writeMessage {
                    Label(message, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.green)
                }

                if model.selectedNote?.isDraft == true {
                    Label(
                        "No Project Notes were found. Enter the lyrics below, then create a Logic copy.",
                        systemImage: "text.badge.plus"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppTheme.cyan)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cyan.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                TextEditor(text: Binding(
                    get: { model.selectedNote?.text ?? "" },
                    set: { value in
                        model.updateSelectedText(value)
                        scheduleHistorySave(value)
                    }
                ))
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .lineSpacing(7)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, minHeight: 500, alignment: .leading)
                    .appPanel(radius: 22, padding: 28)
                    .accessibilityLabel(L10n.text("Lyrics editor"))
                    .accessibilityHint(L10n.text("Edit the lyrics. Changes are saved automatically in local history."))
            }
            .frame(maxWidth: 840)
            .padding(30)
            .frame(maxWidth: .infinity)
        }
    }

    private var heroDropZone: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(AppTheme.accent.opacity(0.12)).frame(width: 130, height: 130)
                Circle().stroke(AppTheme.cyan.opacity(0.25), lineWidth: 1).frame(width: 105, height: 105)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(
                        LinearGradient(colors: [AppTheme.accent, AppTheme.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .accessibilityHidden(true)
            }
            VStack(spacing: 8) {
                Text("Your Lyrics, Directly from Logic")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Drop a .logicx project. No audio file is uploaded or modified.")
                    .foregroundStyle(.secondary)
            }
            Button("Open a Logic Pro Project", systemImage: "folder.badge.plus") { showImporter = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(50)
    }

    private var loadingState: some View {
        VStack(spacing: 15) {
            ProgressView().controlSize(.large)
            Text("Reading Logic Project…").font(.headline)
            Text("Extracting Project Notes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var historyEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppTheme.cyan)
                .accessibilityHidden(true)
            Text("History Is Empty").font(.title3.weight(.semibold))
            Text("Loaded Logic projects will automatically appear here.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(40)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button(selectedMode == .metadata ? L10n.text("Open Audio") : L10n.text("Open"), systemImage: "folder") {
                if selectedMode == .metadata { showAudioImporter = true } else { showImporter = true }
            }
            .keyboardShortcut("o", modifiers: .command)
            .accessibilityLabel(selectedMode == .metadata ? L10n.text("Open Audio") : L10n.text("Open"))
            .accessibilityHint(selectedMode == .metadata
                ? L10n.text("Open an MP3 or WAV file")
                : L10n.text("Open a Logic Pro project"))
            .accessibilityIdentifier("toolbar-open")
            if !showsHistory && selectedMode != .metadata {
                Button("Copy", systemImage: "doc.on.doc") { model.copySelectedNote() }
                    .disabled(model.selectedNote == nil)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .accessibilityLabel(L10n.text("Copy"))
                    .accessibilityHint(L10n.text("Copy the selected project note"))
                    .accessibilityIdentifier("toolbar-copy")
                Menu("Export", systemImage: "square.and.arrow.up") {
                    Button("Text (.txt)") { model.exportSelectedNote(asMarkdown: false) }
                    Button("Markdown (.md)") { model.exportSelectedNote(asMarkdown: true) }
                }
                .disabled(model.selectedNote == nil)
                .accessibilityLabel(L10n.text("Export"))
                .accessibilityHint(L10n.text("Export the selected project note"))
                .accessibilityIdentifier("toolbar-export")
            }
        }
        ToolbarItem {
            switch updater.state {
            case .available(let version):
                Button(L10n.format("Install v%@", version), systemImage: "arrow.down.circle.fill") {
                    confirmsUpdateInstallation = true
                }
                .help(L10n.text("Download, verify, and compile the update automatically"))
                .accessibilityIdentifier("toolbar-updates")
            case .checking:
                ProgressView()
                    .controlSize(.small)
                    .help(L10n.text("Checking for updates"))
                    .accessibilityLabel(L10n.text("Checking for updates"))
                    .accessibilityIdentifier("toolbar-updates")
            case .current:
                Button("Up to Date", systemImage: "checkmark.circle.fill") {
                    updater.check(silent: false)
                }
                .help(L10n.text("Check again"))
                .accessibilityIdentifier("toolbar-updates")
            default:
                Button("Updates", systemImage: "arrow.triangle.2.circlepath") {
                    updater.check(silent: false)
                }
                .help(L10n.text("Check for updates"))
                .accessibilityIdentifier("toolbar-updates")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil || history.persistenceError != nil || updater.errorMessage != nil },
            set: {
                if !$0 {
                    model.errorMessage = nil
                    history.dismissPersistenceError()
                    updater.errorMessage = nil
                }
            }
        )
    }

    private var currentErrorMessage: String {
        model.errorMessage ?? history.persistenceError?.message ?? updater.errorMessage ?? String(localized: "An unexpected error occurred.")
    }

    private var currentAlertTitle: String {
        history.persistenceError?.title ?? L10n.text("Logic Lyrics")
    }

    private var activeOperationState: OperationState {
        history.operationState.isRunning ? history.operationState : model.operationState
    }

    private var cancelActiveOperation: (() -> Void)? {
        if history.operationState.isRunning { return history.cancelTransfer }
        if model.operationState.isRunning { return model.cancelProcessing }
        return nil
    }

    private var availableUpdateVersion: String? {
        if case .available(let version) = updater.state { return version }
        return nil
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            let url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else { url = item as? URL }
            if let url {
                DispatchQueue.main.async {
                    let extensionName = url.pathExtension.lowercased()
                    if ["mp3", "wav", "wave"].contains(extensionName) {
                        openAudio(url)
                    } else if extensionName == "logicx" {
                        openLogicProject(url)
                    } else {
                        model.errorMessage = String(localized: "Unsupported format. Use a .logicx project or an MP3/WAV file.")
                    }
                }
            } else if let error {
                DispatchQueue.main.async {
                    model.errorMessage = String(format: String(localized: "The dropped file cannot be opened: %@"), error.localizedDescription)
                }
            }
        }
        return true
    }

    private func openAudio(_ url: URL) {
        flushHistorySave()
        pendingAudioURL = url
        selectedMode = .metadata
        showsHistory = false
    }

    private func openLogicProject(_ url: URL) {
        flushHistorySave()
        model.open(url)
    }

    private func reopenHistoryProject(_ entryID: UUID) {
        do {
            openLogicProject(try history.resolveProjectURL(entryID: entryID))
        } catch {
            locateHistoryProject(entryID, fallbackError: error)
        }
    }

    private func locateHistoryProject(_ entryID: UUID, fallbackError: Error? = nil) {
        let panel = NSOpenPanel()
        panel.title = L10n.text("Locate Logic Project")
        panel.message = L10n.text("Choose the moved or renamed .logicx project to reconnect it with this history entry.")
        panel.prompt = L10n.text("Reconnect")
        panel.allowedContentTypes = [logicProjectType, .package]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            if let fallbackError { model.errorMessage = fallbackError.localizedDescription }
            return
        }
        do {
            openLogicProject(try history.relocateProject(entryID: entryID, to: url))
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func restoreHistoryRevision(entryID: UUID, lyrics: String) {
        history.restoreRevision(entryID: entryID, lyrics: lyrics)
        if currentHistoryID == entryID { model.updateSelectedText(lyrics) }
    }

    private func revertHistoryEntry(_ entry: SongHistoryEntry) {
        history.revertToProjectLyrics(entryID: entry.id)
        if currentHistoryID == entry.id { model.updateSelectedText(entry.sourceLyrics) }
    }

    private func exportHistory() {
        flushHistorySave()
        history.flush()
        let panel = NSSavePanel()
        panel.title = L10n.text("Export Song History")
        panel.nameFieldStringValue = "LogicLyrics-History.\(HistoryArchiveService.fileExtension)"
        panel.allowedContentTypes = [historyArchiveType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        history.exportHistory(to: destination)
    }

    private func importHistory() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("Import Song History")
        panel.message = L10n.text("Imported songs are merged safely; current local versions are never overwritten.")
        panel.allowedContentTypes = [historyArchiveType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        history.importHistory(from: source)
    }

    private func scheduleHistorySave(_ lyrics: String) {
        historySaveTask?.cancel()
        guard let entryID = currentHistoryID else { return }
        hasPendingHistoryLyricsSave = true
        historySaveTask = Task {
            try? await Task<Never, Never>.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            history.updateLyrics(entryID: entryID, lyrics: lyrics)
            hasPendingHistoryLyricsSave = false
            historySaveTask = nil
        }
    }

    private func flushHistorySave() {
        guard hasPendingHistoryLyricsSave else { return }
        historySaveTask?.cancel()
        historySaveTask = nil
        hasPendingHistoryLyricsSave = false
        guard let entryID = currentHistoryID, let lyrics = model.selectedNote?.text else { return }
        history.updateLyrics(entryID: entryID, lyrics: lyrics)
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }
}
