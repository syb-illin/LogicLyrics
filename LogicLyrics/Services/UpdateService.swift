import AppKit
import Foundation

enum UpdatePreferences {
    static let automaticallyChecksForUpdatesKey = "updates.automaticallyChecksForUpdates"
}

struct UpdateRelease: Sendable {
    let version: String
    let assetNames: Set<String>
}

protocol UpdateReleaseChecking: Sendable {
    func latestRelease() async throws -> UpdateRelease
}

struct GitHubReleaseClient: UpdateReleaseChecking {
    private let session: URLSession
    private let endpoint: URL

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.github.com/repos/syb-illin/LogicLyrics/releases/latest")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    func latestRelease() async throws -> UpdateRelease {
        var request = URLRequest(url: endpoint)
        request.setValue("LogicLyrics-macOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(Response.self, from: data)
        return UpdateRelease(
            version: release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            assetNames: Set(release.assets.map(\.name))
        )
    }

    private struct Response: Decodable {
        let tagName: String
        let assets: [Asset]

        struct Asset: Decodable { let name: String }
        enum CodingKeys: String, CodingKey { case tagName = "tag_name"; case assets }
    }
}

@MainActor
final class UpdateService: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case current
        case available(version: String)
    }

    @Published private(set) var state = State.idle
    @Published var errorMessage: String?
    private let releaseClient: any UpdateReleaseChecking
    private var checkTask: Task<Void, Never>?

    init(releaseClient: any UpdateReleaseChecking = GitHubReleaseClient()) {
        self.releaseClient = releaseClient
    }

    func check(silent: Bool = true) {
        if silent, state != .idle {
            AppLog.updates.debug("Redundant automatic update check skipped")
            return
        }
        guard state != .checking else { return }
        checkTask?.cancel()
        state = .checking
        let startedAt = Date()
        let trigger = silent ? "automatic" : "manual"
        AppLog.updates.info("Update check started trigger=\(trigger, privacy: .public)")
        let releaseClient = releaseClient
        checkTask = Task { [weak self, releaseClient, startedAt] in
            do {
                let release = try await releaseClient.latestRelease()
                try Task<Never, Never>.checkCancellation()
                guard !release.version.isEmpty else { throw UpdateError.invalidRelease }
                guard release.assetNames.contains("LogicLyrics-macOS-source.zip"),
                      release.assetNames.contains("LogicLyrics-macOS-source.zip.sha256") else {
                    throw UpdateError.incompleteRelease
                }
                guard let self else { return }
                state = Self.isNewer(release.version, than: Self.currentVersion)
                    ? .available(version: release.version)
                    : .current
                let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                AppLog.updates.info("Update check succeeded duration_ms=\(durationMilliseconds, privacy: .public) remote_version=\(release.version, privacy: .public)")
            } catch is CancellationError {
                AppLog.updates.notice("Update check cancelled")
                return
            } catch {
                guard let self else { return }
                let errorType = String(describing: type(of: error))
                AppLog.updates.error("Update check failed error_type=\(errorType, privacy: .public)")
                state = .idle
                if !silent { errorMessage = L10n.format("Unable to check for updates: %@", error.localizedDescription) }
            }
        }
    }

    func installAvailableUpdate() {
        guard case .available = state,
              let bundled = Bundle.main.url(forResource: "UPDATE", withExtension: "command") else {
            errorMessage = L10n.text("The updater is missing from the application.")
            return
        }
        do {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.local.LogicLyrics/updater", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let executable = directory.appendingPathComponent("UPDATE.command")
            let targetFile = directory.appendingPathComponent("target-path.txt")
            let currentApplication = Bundle.main.bundleURL.standardizedFileURL
            guard currentApplication.pathExtension.lowercased() == "app",
                  FileManager.default.isWritableFile(atPath: currentApplication.deletingLastPathComponent().path) else {
                throw UpdateError.unwritableInstallation
            }
            let data = try Data(contentsOf: bundled)
            try data.write(to: executable, options: .atomic)
            try Data(currentApplication.path.utf8).write(to: targetFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            guard NSWorkspace.shared.open(executable) else { throw UpdateError.cannotLaunch }
            AppLog.updates.notice("Updater launched")
        } catch {
            let errorType = String(describing: type(of: error))
            AppLog.updates.error("Updater launch failed error_type=\(errorType, privacy: .public)")
            errorMessage = L10n.format("The updater could not be launched: %@", error.localizedDescription)
        }
    }

    private enum UpdateError: LocalizedError {
        case invalidRelease
        case incompleteRelease
        case unwritableInstallation
        case cannotLaunch

        var errorDescription: String? {
            switch self {
            case .invalidRelease:
                L10n.text("The release version is missing or invalid.")
            case .incompleteRelease:
                L10n.text("The release does not contain the two required update files.")
            case .unwritableInstallation:
                L10n.text("The app is installed in a read-only folder. Move it to Downloads or Applications with the required permissions.")
            case .cannotLaunch:
                L10n.text("macOS could not open the updater in Terminal.")
            }
        }
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        let currentParts = current.split(separator: ".", omittingEmptySubsequences: false)
        guard !candidateParts.isEmpty, !currentParts.isEmpty,
              candidateParts.allSatisfy({ Int($0) != nil }),
              currentParts.allSatisfy({ Int($0) != nil }) else { return false }
        let left = candidateParts.compactMap { Int($0) }
        let right = currentParts.compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }
}
