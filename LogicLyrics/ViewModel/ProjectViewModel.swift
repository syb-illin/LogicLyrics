import AppKit
import Foundation

/// Main-actor presentation model for the app's single responsibility:
/// reading a Logic project and exposing its Project Notes as lyrics.
@MainActor
final class ProjectViewModel: ObservableObject {
    typealias ProjectLoadedHandler = (String, URL, [ExtractedNote], Double?, String?) -> Void

    @Published private(set) var projectName = ""
    @Published private(set) var notes: [ExtractedNote] = []
    @Published private(set) var bpm: Double?
    @Published private(set) var musicalKey: String?
    @Published private(set) var projectURL: URL?
    @Published var selectedNoteID: String? { didSet { refreshSections() } }
    @Published private(set) var sections: [LyricSection] = []
    @Published private(set) var operationState = OperationState.idle
    @Published private(set) var didCopy = false
    @Published var errorMessage: String?

    var onProjectLoaded: ProjectLoadedHandler?

    private let reader: any LogicProjectReading
    private var operationTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var operationID = UUID()

    init(reader: any LogicProjectReading = LogicProjectReader()) {
        self.reader = reader
    }

    deinit {
        operationTask?.cancel()
        feedbackTask?.cancel()
    }

    var isLoading: Bool { operationState.isRunning }

    var selectedNote: ExtractedNote? {
        notes.first { $0.id == selectedNoteID } ?? notes.first
    }

    func open(_ url: URL) {
        operationTask?.cancel()
        feedbackTask?.cancel()
        didCopy = false

        let operationID = UUID()
        self.operationID = operationID
        operationState = .running(message: L10n.text("Analyzing Logic project…"), startedAt: Date())
        errorMessage = nil

        let reader = reader
        let startedAt = ProcessInfo.processInfo.systemUptime
        AppLog.projects.info("Logic project analysis started")
        operationTask = Task.detached(priority: .userInitiated) { [weak self, reader] in
            do {
                try Task<Never, Never>.checkCancellation()
                let result = try reader.readProject(at: url)
                try Task<Never, Never>.checkCancellation()
                let durationMilliseconds = Int(
                    (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                )
                AppLog.projects.info(
                    "Logic project analysis succeeded duration_ms=\(durationMilliseconds, privacy: .public) notes=\(result.notes.count, privacy: .public)"
                )
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

    func copySelectedNote() {
        guard let text = selectedNote?.text, !text.isEmpty else { return }
        copy(text)
    }

    func copySection(_ section: LyricSection) {
        copy(section.fullText)
    }

    func cancelProcessing() {
        guard operationState.isRunning else { return }
        operationTask?.cancel()
        if case .running(_, let startedAt) = operationState {
            operationState = .running(message: L10n.text("Cancelling…"), startedAt: startedAt)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
        AppLog.ui.debug("Lyrics copied to pasteboard characters=\(text.count, privacy: .public)")
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task<Never, Never>.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
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

    private func finishOperation(_ operationID: UUID) {
        guard self.operationID == operationID else { return }
        operationState = .idle
        operationTask = nil
    }

    private func refreshSections() {
        sections = selectedNote.map { LyricSectionParser.parse($0.text) } ?? []
    }
}
