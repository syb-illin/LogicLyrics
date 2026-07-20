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
    @StateObject private var model = ProjectViewModel()
    @StateObject private var history = HistoryStore()
    @StateObject private var updater = UpdateService()
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
    @State private var confirmsLogicWrite = false

    private let logicProjectType = UTType(filenameExtension: "logicx") ?? UTType.package

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
                if let url = urls.first { model.open(url) }
            case .failure(let error):
                model.errorMessage = "Ouverture du projet impossible : \(error.localizedDescription)"
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
                model.errorMessage = "Ouverture du fichier audio impossible : \(error.localizedDescription)"
            }
        }
        .alert("Logic Lyrics", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(currentErrorMessage)
        }
        .alert(model.selectedNote?.isDraft == true ? "Ajouter ces paroles à une copie Logic ?" : "Créer une copie Logic expérimentale ?", isPresented: $confirmsLogicWrite) {
            Button("Annuler", role: .cancel) {}
            Button("Créer la copie") { model.createEditedProjectCopy() }
        } message: {
            Text("L’original ne sera jamais modifié. L’app reconnaît et met à jour la structure terminale des Notes, puis relit la copie. Logic Pro devra confirmer la compatibilité finale à l’ouverture.")
        }
        .onAppear {
            updater.check(silent: true)
            model.onProjectLoaded = { name, path, notes, bpm, musicalKey in
                var restored = [String: String]()
                var identifiers = [String: UUID]()
                for note in notes {
                    let identifier = history.recordProject(
                        name: name, path: path, noteKey: note.id, alternative: note.alternative,
                        lyrics: note.text, bpm: bpm, musicalKey: musicalKey
                    )
                    identifiers[note.id] = identifier
                    if let saved = history.entry(id: identifier)?.lyrics { restored[note.id] = saved }
                }
                historyIDsByNote = identifiers
                currentHistoryID = notes.first.flatMap { identifiers[$0.id] }
                selectedHistoryID = nil
                showsHistory = false
                return restored
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                flushHistorySave()
                history.flush()
            }
        }
        .overlay { ProcessingOverlay(state: model.operationState, cancel: model.cancelProcessing) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader
            Divider().opacity(0.35)

            if showsHistory {
                historySidebar
            } else if model.notes.isEmpty {
                compactEmptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        projectCard
                        notePicker
                        if !model.sections.isEmpty { sectionPicker }
                    }
                    .padding(14)
                }
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .trailing) { Divider().opacity(0.25) }
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            AccentIcon(systemName: "waveform.and.mic", size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Logic Lyrics").font(.headline)
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
            .help(selectedMode == .metadata ? "Ouvrir un fichier MP3 ou WAV" : "Ouvrir un projet Logic Pro")
            Button {
                showsHistory.toggle()
                if showsHistory { selectedHistoryID = history.entries.first?.id }
            } label: {
                Image(systemName: showsHistory ? "clock.fill" : "clock")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(showsHistory ? AppTheme.cyan.opacity(0.18) : Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Historique des morceaux")
        }
        .padding(16)
    }

    private var compactEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppTheme.cyan)
            VStack(spacing: 6) {
                Text(selectedMode == .metadata ? "Dépose un export Suno" : "Dépose un projet").font(.headline)
                Text(selectedMode == .metadata
                     ? "Glisse un fichier MP3 ou WAV\npour lire et écrire ses métadonnées"
                     : "Glisse un fichier .logicx\npour extraire ses paroles")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button(selectedMode == .metadata ? "Choisir MP3/WAV" : "Choisir un projet") {
                if selectedMode == .metadata { showAudioImporter = true } else { showImporter = true }
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var historySidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher", text: $history.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(14)

            if history.filteredEntries.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("Aucun morceau dans l’historique")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(history.filteredEntries) { entry in
                            Button {
                                selectedHistoryID = entry.id
                            } label: {
                                HStack(spacing: 11) {
                                    AccentIcon(systemName: "music.note", color: AppTheme.cyan, size: 34)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.projectName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text([
                                            entry.alternative.isEmpty ? nil : "Alt. \(entry.alternative)",
                                            entry.updatedAt.formatted(date: .abbreviated, time: .omitted)
                                        ].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !entry.prompt.isEmpty {
                                        Image(systemName: "sparkles")
                                            .font(.caption).foregroundStyle(AppTheme.accent)
                                    }
                                }
                                .padding(10)
                                .background(selectedHistoryID == entry.id ? AppTheme.cyan.opacity(0.13) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                }
            }
        }
    }

    private var projectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                AccentIcon(systemName: "music.note", color: AppTheme.cyan, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.projectName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(model.sections.count) sections détectées")
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
                    value: model.bpm.map { Self.formatBPM($0) + " BPM" } ?? "Non détecté",
                    systemName: "metronome",
                    color: AppTheme.cyan
                )
                projectMetadata(
                    title: "TONALITÉ",
                    value: model.musicalKey ?? "Non détectée",
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
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 1)
        }
    }

    private var notePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarTitle("NOTES DU PROJET")
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
                            Text("Alternative \(note.alternative)")
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
                    .help("Copier cette section")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }

    private func sidebarTitle(_ value: String) -> some View {
        Text(value)
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
                    HistoryDetailView(entry: entry) {
                        history.delete(id: entry.id)
                        selectedHistoryID = history.entries.first?.id
                    }
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
                Text(showsHistory ? "Historique" : workspaceTitle)
                    .font(.title3.weight(.semibold))
                Text(showsHistory
                     ? "Morceaux, paroles et prompts sauvegardés sur ce Mac"
                     : workspaceSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsHistory {
                Button("Retour au projet", systemImage: "arrow.left") { showsHistory = false }
                    .buttonStyle(.bordered)
            } else {
                Picker("Vue", selection: $selectedMode) {
                    Label("Paroles", systemImage: "text.alignleft").tag(WorkspaceMode.lyrics)
                    Label("Suno AI", systemImage: "sparkles").tag(WorkspaceMode.suno)
                    Label("Tags audio", systemImage: "tag.fill").tag(WorkspaceMode.metadata)
                }
                .pickerStyle(.segmented)
                .frame(width: 390)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var workspaceTitle: String {
        switch selectedMode {
        case .lyrics: "Paroles"
        case .suno: "Suno Studio"
        case .metadata: "Métadonnées audio"
        }
    }

    private var workspaceSubtitle: String {
        switch selectedMode {
        case .lyrics: "Notes extraites du projet Logic"
        case .suno: "Prépare un prompt vocalement fidèle"
        case .metadata: "Tague les exports Suno MP3 et WAV"
        }
    }

    private var lyricsReader: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.selectedNote?.title ?? "Paroles")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("\(model.sections.count) sections • édition et sauvegarde automatiques")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.selectedNote?.isDraft == true ? "Ajouter à une copie Logic" : "Copie Logic", systemImage: "doc.on.doc.fill") {
                        flushHistorySave()
                        confirmsLogicWrite = true
                    }
                    .buttonStyle(.bordered)
                    .help("Créer une copie .logicx contenant ces paroles, sans toucher à l’original")
                    .disabled(model.selectedNote?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                    Button(model.didCopy ? "Copié" : "Tout copier", systemImage: model.didCopy ? "checkmark" : "doc.on.doc") {
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
                        "Aucune Note de projet n’a été trouvée. Écris les paroles ci-dessous, puis crée une copie Logic.",
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
            }
            VStack(spacing: 8) {
                Text("Tes paroles, directement depuis Logic")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Dépose un projet .logicx. Aucun fichier audio n’est envoyé ni modifié.")
                    .foregroundStyle(.secondary)
            }
            Button("Ouvrir un projet Logic Pro", systemImage: "folder.badge.plus") { showImporter = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(50)
    }

    private var loadingState: some View {
        VStack(spacing: 15) {
            ProgressView().controlSize(.large)
            Text("Lecture du projet Logic…").font(.headline)
            Text("Extraction des Notes de projet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var historyEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppTheme.cyan)
            Text("Historique vide").font(.title3.weight(.semibold))
            Text("Les projets Logic chargés apparaîtront automatiquement ici.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(40)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button(selectedMode == .metadata ? "Ouvrir un audio" : "Ouvrir", systemImage: "folder") {
                if selectedMode == .metadata { showAudioImporter = true } else { showImporter = true }
            }
            if selectedMode != .metadata {
                Button("Copier", systemImage: "doc.on.doc") { model.copySelectedNote() }
                    .disabled(model.selectedNote == nil)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Menu("Exporter", systemImage: "square.and.arrow.up") {
                    Button("Texte (.txt)") { model.exportSelectedNote(asMarkdown: false) }
                    Button("Markdown (.md)") { model.exportSelectedNote(asMarkdown: true) }
                }
                .disabled(model.selectedNote == nil)
            }
        }
        ToolbarItem {
            switch updater.state {
            case .available(let version):
                Button("Installer v\(version)", systemImage: "arrow.down.circle.fill") {
                    updater.installAvailableUpdate()
                }
                .help("Télécharger, vérifier et compiler automatiquement la mise à jour")
            case .checking:
                ProgressView().controlSize(.small).help("Recherche d’une mise à jour")
            default:
                Button("Mises à jour", systemImage: "arrow.triangle.2.circlepath") {
                    updater.check(silent: false)
                }
                .help("Vérifier les mises à jour")
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
        model.errorMessage ?? history.persistenceError?.message ?? updater.errorMessage ?? "Une erreur inattendue est survenue."
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
                        model.open(url)
                    } else {
                        model.errorMessage = "Format non accepté. Utilise un projet .logicx ou un fichier MP3/WAV."
                    }
                }
            } else if let error {
                DispatchQueue.main.async {
                    model.errorMessage = "Le fichier déposé ne peut pas être ouvert : \(error.localizedDescription)"
                }
            }
        }
        return true
    }

    private func openAudio(_ url: URL) {
        pendingAudioURL = url
        selectedMode = .metadata
        showsHistory = false
    }

    private func scheduleHistorySave(_ lyrics: String) {
        historySaveTask?.cancel()
        guard let entryID = currentHistoryID else { return }
        historySaveTask = Task {
            try? await Task<Never, Never>.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            history.updateLyrics(entryID: entryID, lyrics: lyrics)
        }
    }

    private func flushHistorySave() {
        historySaveTask?.cancel()
        guard let entryID = currentHistoryID, let lyrics = model.selectedNote?.text else { return }
        history.updateLyrics(entryID: entryID, lyrics: lyrics)
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
