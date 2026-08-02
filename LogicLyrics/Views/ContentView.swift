import AppKit
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Composition root for the Logic-reading workspace. File acquisition,
/// history coordination and update state live here; rendering is delegated to
/// focused child views so the main flow remains easy to reason about and test.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var updater: UpdateService
    @AppStorage(UpdatePreferences.automaticallyChecksForUpdatesKey)
    private var automaticallyChecksForUpdates = true

    @StateObject private var model = ProjectViewModel()
    @StateObject private var history: HistoryStore
    @State private var isDropTargeted = false
    @State private var presentsProjectImporter = false
    @State private var selectedHistoryID: UUID?
    @State private var confirmsUpdateInstallation = false

    private let logicProjectType = UTType(filenameExtension: "logicx") ?? .package

    init() {
        _history = StateObject(wrappedValue: HistoryStore.configuredForCurrentProcess())
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 260, ideal: 292, max: 340)
            } detail: {
                workspace
            }
            .navigationSplitViewStyle(.balanced)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Logic Lyrics workspace"))
        .accessibilityIdentifier("logic-lyrics-workspace")
        .tint(AppTheme.accent)
        .navigationTitle(model.projectName.isEmpty ? L10n.text("Logic Lyrics") : model.projectName)
        .toolbar { toolbar }
        .focusedSceneValue(
            \.openLogicProjectAction,
            OpenLogicProjectAction(perform: requestProjectImport)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: receiveDrop)
        .fileImporter(
            isPresented: $presentsProjectImporter,
            allowedContentTypes: [logicProjectType, .package],
            allowsMultipleSelection: false
        ) { result in
            handleProjectImport(result)
        }
        .alert(currentAlertTitle, isPresented: errorBinding) {
            Button(L10n.text("OK"), role: .cancel) {
                model.errorMessage = nil
                history.dismissPersistenceError()
                updater.errorMessage = nil
            }
        } message: {
            Text(currentErrorMessage)
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
        .onAppear(perform: configureSession)
        .onDisappear {
            model.onProjectLoaded = nil
            history.flush()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { history.flush() }
        }
        .overlay {
            ProcessingOverlay(state: model.operationState, cancel: model.cancelProcessing)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader
            Divider().opacity(0.3)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if model.selectedNote != nil { currentProjectCard }
                    RecentProjectsView(
                        history: history,
                        selectedID: selectedHistoryID,
                        onSelect: { selectedHistoryID = $0 }
                    )
                }
                .padding(14)
            }
        }
        .background {
            if reduceTransparency {
                Color(red: 0.055, green: 0.057, blue: 0.067)
            } else {
                Color.black.opacity(0.16)
            }
        }
        .overlay(alignment: .trailing) { Divider().opacity(0.25) }
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            AccentIcon(systemName: "waveform.and.mic", size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.text("Logic Lyrics"))
                    .font(.headline)
                    .accessibilityIdentifier("logic-lyrics-root")
                Text(L10n.text("Logic Project Reader"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.format("v%@ · build %@", Self.appVersion, Self.buildNumber))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Button(action: requestProjectImport) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(L10n.text("Open a Logic Pro project"))
            .accessibilityLabel(L10n.text("Open Logic project"))
            .accessibilityHint(L10n.text("Opens a file picker. Drag and drop remains available as an alternative."))
        }
        .padding(16)
    }

    private var currentProjectCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button {
                selectedHistoryID = nil
            } label: {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 10) {
                        AccentIcon(systemName: "music.note", color: AppTheme.cyan, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.projectName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(L10n.format("Alternative %@", model.selectedNote?.alternative ?? "—"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        CapsuleStatus(text: L10n.text("Logic"), systemName: "checkmark")
                    }

                    HStack(spacing: 8) {
                        metadataTile(
                            title: L10n.text("TEMPO"),
                            value: model.bpm.map { Self.formatBPM($0) + " BPM" } ?? L10n.text("Not detected"),
                            systemName: "metronome",
                            color: AppTheme.cyan
                        )
                        metadataTile(
                            title: L10n.text("KEY"),
                            value: model.musicalKey ?? L10n.text("Not detected"),
                            systemName: "music.note",
                            color: AppTheme.accent
                        )
                    }

                    if !model.sections.isEmpty {
                        Divider().opacity(0.25)
                        Text(L10n.format("%d sections detected", model.sections.count))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.format("Current Logic project: %@", model.projectName))
            .accessibilityHint(L10n.text("Shows the currently loaded project lyrics."))
            .accessibilityIdentifier("current-project-card")

            if model.notes.count > 1 {
                Picker(L10n.text("Project Notes"), selection: $model.selectedNoteID) {
                    ForEach(model.notes) { note in
                        Text(note.title).tag(Optional(note.id))
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .appPanel(radius: 15, padding: 13)
    }

    private func metadataTile(
        title: String,
        value: String,
        systemName: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
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
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("%@: %@", title, value))
    }

    private var workspace: some View {
        Group {
            if let entry = history.entry(id: selectedHistoryID) {
                LyricsReaderView(document: .history(entry), onOpenProject: {
                    reopenHistoryProject(entry.id)
                })
            } else if let note = model.selectedNote {
                LyricsReaderView(
                    document: .project(
                        name: model.projectName,
                        note: note,
                        bpm: model.bpm,
                        musicalKey: model.musicalKey
                    )
                )
            } else {
                emptyWorkspace
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.10))
        .overlay { dropTargetOverlay }
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 22) {
            AccentIcon(systemName: "text.document", color: AppTheme.accent, size: 72)
            VStack(spacing: 8) {
                Text(L10n.text("Lyrics from Logic, without the clutter"))
                    .font(.title.weight(.semibold))
                Text(L10n.text("Open or drop a .logicx project to read its Project Notes, tempo and key."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            Button(L10n.text("Open a Logic Pro Project"), systemImage: "folder.badge.plus", action: requestProjectImport)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("empty-open-project")
            Text(L10n.text("Your project stays on this Mac and is never modified."))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Logic project import"))
    }

    @ViewBuilder
    private var dropTargetOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.cyan, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                .background(AppTheme.cyan.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button(L10n.text("Open"), systemImage: "folder", action: requestProjectImport)
                .accessibilityLabel(L10n.text("Open Logic project"))
                .accessibilityHint(L10n.text("Open a Logic Pro project"))
                .accessibilityIdentifier("toolbar-open")
            if model.selectedNote != nil, selectedHistoryID == nil {
                Button(model.didCopy ? L10n.text("Copied") : L10n.text("Copy Lyrics"),
                       systemImage: model.didCopy ? "checkmark" : "doc.on.doc") {
                    model.copySelectedNote()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .accessibilityIdentifier("toolbar-copy")
            }
        }
        ToolbarItem { updateControl }
    }

    @ViewBuilder
    private var updateControl: some View {
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
            Button(L10n.text("Up to Date"), systemImage: "checkmark.circle") {
                updater.check(silent: false)
            }
            .help(L10n.text("Check again"))
            .accessibilityIdentifier("toolbar-updates")
        case .idle:
            Button(L10n.text("Updates"), systemImage: "arrow.triangle.2.circlepath") {
                updater.check(silent: false)
            }
            .help(L10n.text("Check for updates"))
            .accessibilityIdentifier("toolbar-updates")
        }
    }

    private func configureSession() {
        if automaticallyChecksForUpdates && !Self.isUITesting {
            updater.check(silent: true)
        } else {
            AppLog.updates.info("Automatic update check skipped")
        }
        model.onProjectLoaded = { name, url, notes, bpm, musicalKey in
            for note in notes {
                history.recordProject(
                    name: name,
                    url: url,
                    noteKey: note.id,
                    alternative: note.alternative,
                    lyrics: note.text,
                    bpm: bpm,
                    musicalKey: musicalKey
                )
            }
            selectedHistoryID = nil
        }
    }

    private func requestProjectImport() {
        AppLog.ui.debug("Logic project picker requested")
        presentsProjectImporter = true
    }

    private func handleProjectImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first { openProject(url) }
        case .failure(let error):
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain,
               cocoaError.code == CocoaError.Code.userCancelled.rawValue {
                AppLog.ui.debug("Logic project picker cancelled")
                return
            }
            let errorType = String(describing: type(of: error))
            AppLog.ui.error("Logic project picker failed error_type=\(errorType, privacy: .public)")
            model.errorMessage = L10n.format("Unable to open the project: %@", error.localizedDescription)
        }
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }
            DispatchQueue.main.async {
                if let url, url.pathExtension.lowercased() == "logicx" {
                    openProject(url)
                } else if let error {
                    model.errorMessage = L10n.format(
                        "The dropped file cannot be opened: %@", error.localizedDescription
                    )
                } else {
                    model.errorMessage = L10n.text("Unsupported format. Choose a .logicx project.")
                }
            }
        }
        return true
    }

    private func openProject(_ url: URL) {
        selectedHistoryID = nil
        model.open(url)
    }

    private func reopenHistoryProject(_ entryID: UUID) {
        do {
            openProject(try history.resolveProjectURL(entryID: entryID))
        } catch {
            locateHistoryProject(entryID, fallbackError: error)
        }
    }

    private func locateHistoryProject(_ entryID: UUID, fallbackError: Error) {
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
            model.errorMessage = fallbackError.localizedDescription
            return
        }
        do {
            openProject(try history.relocateProject(entryID: entryID, to: url))
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: {
                model.errorMessage != nil
                    || history.persistenceError != nil
                    || updater.errorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    model.errorMessage = nil
                    history.dismissPersistenceError()
                    updater.errorMessage = nil
                }
            }
        )
    }

    private var currentErrorMessage: String {
        model.errorMessage
            ?? history.persistenceError?.message
            ?? updater.errorMessage
            ?? L10n.text("An unexpected error occurred.")
    }

    private var currentAlertTitle: String {
        history.persistenceError?.title ?? L10n.text("Logic Lyrics")
    }

    private var availableUpdateVersion: String? {
        if case .available(let version) = updater.state { return version }
        return nil
    }

    private static func formatBPM(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
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
