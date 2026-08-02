import Foundation

/// Main-actor presentation model for the app's single responsibility:
/// reading one Logic project and exposing its Project Notes as lyrics.
@MainActor
final class ProjectViewModel: ObservableObject {
    typealias ProjectLoadedHandler = (String, URL, LogicProjectReader.Result) -> Void

    @Published private(set) var projectName = ""
    @Published private(set) var notes: [ExtractedNote] = []
    @Published private(set) var bpm: Double?
    @Published private(set) var musicalKey: String?
    @Published private(set) var projectURL: URL?
    @Published private(set) var sections: [LyricSection] = []
    @Published private(set) var availableAlternatives: [String] = []
    @Published private(set) var selectedAlternativeName = ""
    @Published private(set) var diagnostics: ExtractionDiagnostics?
    @Published private(set) var isSourceModified = false
    @Published private(set) var operationState = OperationState.idle
    @Published var errorMessage: String?

    var onProjectLoaded: ProjectLoadedHandler?

    private let reader: any LogicProjectReading
    private var operationTask: Task<Void, Never>?
    private var changeDetectionTask: Task<Void, Never>?
    private var operationID = UUID()
    private var sourceStateToken: String?

    init(reader: any LogicProjectReading = LogicProjectReader()) {
        self.reader = reader
    }

    deinit {
        operationTask?.cancel()
        changeDetectionTask?.cancel()
    }

    var isLoading: Bool { operationState.isRunning }
    var selectedNote: ExtractedNote? { notes.first }

    func open(_ url: URL, preferredAlternative: String? = nil) {
        startReading(url, preferredAlternative: preferredAlternative)
    }

    func refresh() {
        guard let projectURL else { return }
        startReading(projectURL, preferredAlternative: selectedAlternativeName)
    }

    func selectAlternative(_ alternative: String) {
        guard availableAlternatives.contains(alternative),
              alternative != selectedAlternativeName,
              let projectURL else { return }
        startReading(projectURL, preferredAlternative: alternative)
    }

    func checkForExternalChanges() {
        guard !isLoading,
              let projectURL,
              let sourceStateToken else { return }
        changeDetectionTask?.cancel()
        let reader = reader
        let alternative = selectedAlternativeName
        changeDetectionTask = Task.detached(priority: .utility) { [weak self, reader] in
            do {
                let current = try reader.projectStateToken(
                    at: projectURL,
                    preferredAlternative: alternative
                )
                try Task<Never, Never>.checkCancellation()
                await self?.completeChangeDetection(current != sourceStateToken)
            } catch is CancellationError {
                return
            } catch {
                let errorType = String(describing: type(of: error))
                AppLog.projects.debug(
                    "Logic project state check skipped error_type=\(errorType, privacy: .public)"
                )
            }
        }
    }

    func cancelProcessing() {
        guard operationState.isRunning else { return }
        operationTask?.cancel()
        if case .running(_, let startedAt) = operationState {
            operationState = .running(message: L10n.text("Cancelling…"), startedAt: startedAt)
        }
    }

    private func startReading(_ url: URL, preferredAlternative: String?) {
        operationTask?.cancel()
        changeDetectionTask?.cancel()
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
                let result = try reader.readProject(
                    at: url,
                    preferredAlternative: preferredAlternative
                )
                try Task<Never, Never>.checkCancellation()
                let duration = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
                AppLog.projects.info(
                    "Logic project analysis succeeded duration_ms=\(duration, privacy: .public) candidates=\(result.diagnostics.decodedCandidateCount, privacy: .public)"
                )
                await self?.completeOpen(result: result, url: url, operationID: operationID)
            } catch is CancellationError {
                await self?.finishOperation(operationID)
            } catch {
                let errorType = String(describing: type(of: error))
                AppLog.projects.error(
                    "Logic project analysis failed error_type=\(errorType, privacy: .public)"
                )
                await self?.failOpen(error, operationID: operationID)
            }
        }
    }

    private func completeOpen(
        result: LogicProjectReader.Result,
        url: URL,
        operationID: UUID
    ) {
        guard self.operationID == operationID else { return }
        projectName = url.deletingPathExtension().lastPathComponent
        projectURL = url
        notes = result.notes
        bpm = result.bpm
        musicalKey = result.musicalKey
        availableAlternatives = result.availableAlternatives
        selectedAlternativeName = result.selectedAlternative
        diagnostics = result.diagnostics
        sourceStateToken = result.sourceStateToken
        isSourceModified = false
        sections = result.notes.first.map { LyricSectionParser.parse($0.text) } ?? []
        onProjectLoaded?(projectName, url, result)
        finishOperation(operationID)
    }

    private func failOpen(_ error: Error, operationID: UUID) {
        guard self.operationID == operationID else { return }
        // A failed refresh must not erase the last successfully read snapshot.
        if projectURL == nil {
            projectName = ""
            notes = []
            bpm = nil
            musicalKey = nil
            availableAlternatives = []
            selectedAlternativeName = ""
            diagnostics = nil
            sourceStateToken = nil
            sections = []
        }
        errorMessage = error.localizedDescription
        finishOperation(operationID)
    }

    private func finishOperation(_ operationID: UUID) {
        guard self.operationID == operationID else { return }
        operationState = .idle
        operationTask = nil
    }

    private func completeChangeDetection(_ changed: Bool) {
        isSourceModified = changed
        changeDetectionTask = nil
    }
}
