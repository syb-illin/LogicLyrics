import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ProjectViewModel: ObservableObject {
    /// Observes a completed project load so history can record it. The callback
    /// deliberately cannot return replacement lyrics: the open Logic project is
    /// always the source of truth for the current editor session.
    var onProjectLoaded: ((String, URL, [ExtractedNote], Double?, String?) -> Void)?
    @Published private(set) var projectName = ""
    @Published private(set) var notes: [ExtractedNote] = []
    @Published private(set) var bpm: Double?
    @Published private(set) var musicalKey: String?
    @Published private(set) var projectURL: URL?
    @Published var selectedNoteID: String? { didSet { refreshSections() } }
    @Published private(set) var sections: [LyricSection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var operationState = OperationState.idle
    @Published private(set) var didCopy = false
    @Published var errorMessage: String?
    @Published var writeMessage: String?
    private let reader: any LogicProjectReading
    private let writer: any LogicProjectWriting
    private var operationTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var operationID = UUID()

    init(reader: any LogicProjectReading = LogicProjectReader(), writer: any LogicProjectWriting = LogicProjectWriter()) {
        self.reader = reader
        self.writer = writer
    }

    var selectedNote: ExtractedNote? {
        notes.first { $0.id == selectedNoteID } ?? notes.first
    }

    var suggestedSongTitle: String {
        guard let firstLine = selectedNote?.text.split(whereSeparator: \.isNewline).first else { return projectName }
        let line = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        if line.lowercased().hasPrefix("title:") {
            let title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }
        return projectName
    }

    func open(_ url: URL) {
        operationTask?.cancel()
        let operationID = UUID()
        self.operationID = operationID
        isLoading = true
        operationState = .running(message: L10n.text("Analyzing Logic project…"), startedAt: Date())
        errorMessage = nil
        writeMessage = nil
        let startedAt = Date()
        AppLog.projects.info("Logic project analysis started")

        let reader = reader
        operationTask = Task.detached(priority: .userInitiated) { [weak self, reader, startedAt] in
            do {
                try Task<Never, Never>.checkCancellation()
                let result = try reader.readProject(at: url)
                try Task<Never, Never>.checkCancellation()
                let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                AppLog.projects.info("Logic project analysis succeeded duration_ms=\(durationMilliseconds, privacy: .public) notes=\(result.notes.count, privacy: .public)")
                await self?.completeOpen(result: result, url: url, operationID: operationID)
            } catch is CancellationError {
                AppLog.projects.notice("Logic project analysis cancelled")
                await self?.finishOperation(operationID)
            } catch {
                let errorType = String(describing: type(of: error))
                AppLog.projects.error("Logic project analysis failed error_type=\(errorType, privacy: .public)")
                await self?.failOpen(error, operationID: operationID)
            }
        }
    }

    func createEditedProjectCopy() {
        guard let projectURL, let note = selectedNote else { return }
        guard !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = LogicProjectWriteError.emptyLyrics.localizedDescription
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = safeFilename(projectName) + "-lyrics-edited.logicx"
        panel.allowedContentTypes = [UTType(filenameExtension: "logicx") ?? .package]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.standardizedFileURL.resolvingSymlinksInPath()
                != projectURL.standardizedFileURL.resolvingSymlinksInPath() else {
            errorMessage = LogicProjectWriteError.sourceEqualsDestination.localizedDescription
            return
        }

        operationTask?.cancel()
        let operationID = UUID()
        self.operationID = operationID
        operationState = .running(message: L10n.text("Creating and validating Logic copy…"), startedAt: Date())
        let startedAt = Date()
        AppLog.projects.info("Transactional Logic copy started")
        let writer = writer
        operationTask = Task.detached(priority: .userInitiated) { [weak self, writer, startedAt] in
            do {
                try Task<Never, Never>.checkCancellation()
                let sourceAccess = projectURL.startAccessingSecurityScopedResource()
                let destinationAccess = destination.startAccessingSecurityScopedResource()
                defer {
                    if sourceAccess { projectURL.stopAccessingSecurityScopedResource() }
                    if destinationAccess { destination.stopAccessingSecurityScopedResource() }
                }
                try writer.createEditedCopy(
                    source: projectURL, destination: destination,
                    alternative: note.alternative, originalText: note.sourceText, editedText: note.text
                )
                try Task<Never, Never>.checkCancellation()
                let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                AppLog.projects.info("Transactional Logic copy succeeded duration_ms=\(durationMilliseconds, privacy: .public)")
                await self?.completeWrite(destination: destination, operationID: operationID)
            } catch is CancellationError {
                AppLog.projects.notice("Transactional Logic copy cancelled")
                await self?.finishOperation(operationID)
            } catch {
                let errorType = String(describing: type(of: error))
                AppLog.projects.error("Transactional Logic copy failed error_type=\(errorType, privacy: .public)")
                await self?.failOperation(error, operationID: operationID)
            }
        }
    }

    func updateSelectedText(_ text: String) {
        guard let id = selectedNote?.id, let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
        refreshSections()
    }

    func copySelectedNote() {
        guard let text = selectedNote?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task<Never, Never>.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
    }

    func copySection(_ section: LyricSection) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(section.fullText, forType: .string)
        didCopy = true
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task<Never, Never>.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
    }

    func cancelProcessing() {
        guard operationState.isRunning else { return }
        operationTask?.cancel()
        if case .running(_, let startedAt) = operationState {
            operationState = .running(message: L10n.text("Cancelling…"), startedAt: startedAt)
        }
    }

    func exportSelectedNote(asMarkdown: Bool) {
        guard let note = selectedNote else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = safeFilename(projectName) + (asMarkdown ? ".md" : ".txt")
        let markdownType = UTType(filenameExtension: "md") ?? UTType.plainText
        panel.allowedContentTypes = [asMarkdown ? markdownType : UTType.plainText]
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try note.text.write(to: destination, atomically: true, encoding: .utf8)
            let format = asMarkdown ? "markdown" : "text"
            AppLog.projects.info("Lyrics export succeeded format=\(format, privacy: .public)")
        } catch {
            let errorType = String(describing: type(of: error))
            AppLog.projects.error("Lyrics export failed error_type=\(errorType, privacy: .public)")
            errorMessage = L10n.format("Export failed: %@", error.localizedDescription)
        }
    }

    private func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        return value.components(separatedBy: forbidden).joined(separator: "-")
    }

    private func completeOpen(result: LogicProjectReader.Result, url: URL, operationID: UUID) {
        guard self.operationID == operationID else { return }
        projectName = url.deletingPathExtension().lastPathComponent
        projectURL = url
        notes = result.notes
        bpm = result.bpm
        musicalKey = result.musicalKey
        selectedNoteID = result.notes.first?.id
        onProjectLoaded?(projectName, url, result.notes, result.bpm, result.musicalKey)
        refreshSections()
        finishOperation(operationID)
    }

    private func completeWrite(destination: URL, operationID: UUID) {
        guard self.operationID == operationID else { return }
        writeMessage = L10n.format("Logic copy verified: %@", destination.lastPathComponent)
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        finishOperation(operationID)
    }

    private func failOpen(_ error: Error, operationID: UUID) {
        guard self.operationID == operationID else { return }
        projectName = ""
        notes = []
        bpm = nil
        musicalKey = nil
        projectURL = nil
        selectedNoteID = nil
        sections = []
        errorMessage = error.localizedDescription
        finishOperation(operationID)
    }

    private func failOperation(_ error: Error, operationID: UUID) {
        guard self.operationID == operationID else { return }
        errorMessage = error.localizedDescription
        finishOperation(operationID)
    }

    private func finishOperation(_ operationID: UUID) {
        guard self.operationID == operationID else { return }
        isLoading = false
        operationState = .idle
        operationTask = nil
    }

    private func refreshSections() {
        sections = selectedNote.map { LyricSectionParser.parse($0.text) } ?? []
    }
}
