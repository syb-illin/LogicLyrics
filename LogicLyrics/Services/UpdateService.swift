import AppKit
import Foundation

enum UpdatePreferences {
    static let automaticallyChecksForUpdatesKey = "updates.automaticallyChecksForUpdates"
}

struct UpdateRelease: Equatable, Sendable {
    let version: String
    let sourceArchiveURL: URL?
    let sourceChecksumURL: URL?
    let releasePageURL: URL?
    let releaseNotes: String
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
        let assets = Dictionary(uniqueKeysWithValues: release.assets.map { ($0.name, $0.downloadURL) })
        return UpdateRelease(
            version: release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            sourceArchiveURL: assets["LogicLyrics-macOS-source.zip"],
            sourceChecksumURL: assets["LogicLyrics-macOS-source.zip.sha256"],
            releasePageURL: release.htmlURL,
            releaseNotes: release.body ?? ""
        )
    }

    private struct Response: Decodable {
        let tagName: String
        let assets: [Asset]
        let htmlURL: URL?
        let body: String?

        struct Asset: Decodable {
            let name: String
            let downloadURL: URL
            enum CodingKeys: String, CodingKey {
                case name
                case downloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
            case htmlURL = "html_url"
            case body
        }
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

    enum UpdateError: LocalizedError {
        case invalidRelease
        case incompleteRelease
        case missingUpdater
        case unwritableInstallation
        case cannotLaunch

        var errorDescription: String? {
            switch self {
            case .invalidRelease:
                L10n.text("The release version is missing or invalid.")
            case .incompleteRelease:
                L10n.text("The release does not contain the two required update files.")
            case .missingUpdater:
                L10n.text("The updater is missing from the application.")
            case .unwritableInstallation:
                L10n.text("The app is installed in a read-only folder. Move it to Downloads or Applications with the required permissions.")
            case .cannotLaunch:
                L10n.text("macOS could not open the updater in Terminal.")
            }
        }
    }

    @Published private(set) var state = State.idle
    @Published private(set) var availableRelease: UpdateRelease?
    @Published var errorMessage: String?
    private let releaseClient: any UpdateReleaseChecking
    private let installer: any UpdateInstalling
    private var checkTask: Task<Void, Never>?

    init(
        releaseClient: any UpdateReleaseChecking = GitHubReleaseClient(),
        installer: any UpdateInstalling = TerminalUpdateInstaller()
    ) {
        self.releaseClient = releaseClient
        self.installer = installer
    }

    deinit { checkTask?.cancel() }

    func check(silent: Bool = true) {
        if silent, state != .idle {
            AppLog.updates.debug("Redundant automatic update check skipped")
            return
        }
        guard state != .checking else { return }
        checkTask?.cancel()
        state = .checking
        errorMessage = nil
        let startedAt = Date()
        let trigger = silent ? "automatic" : "manual"
        AppLog.updates.info("Update check started trigger=\(trigger, privacy: .public)")
        let releaseClient = releaseClient
        checkTask = Task { [weak self, releaseClient, startedAt] in
            do {
                let release = try await releaseClient.latestRelease()
                try Task<Never, Never>.checkCancellation()
                try Self.validate(release)
                guard let self else { return }
                if Self.isNewer(release.version, than: Self.currentVersion) {
                    availableRelease = release
                    state = .available(version: release.version)
                } else {
                    availableRelease = nil
                    state = .current
                }
                let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
                AppLog.updates.info(
                    "Update check succeeded duration_ms=\(duration, privacy: .public) remote_version=\(release.version, privacy: .public)"
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                availableRelease = nil
                state = .idle
                if !silent {
                    errorMessage = L10n.format(
                        "Unable to check for updates: %@",
                        error.localizedDescription
                    )
                }
            }
        }
    }

    func installAvailableUpdate() {
        guard case .available(let version) = state,
              let release = availableRelease,
              release.version == version else {
            errorMessage = L10n.text("The updater is missing from the application.")
            return
        }
        do {
            try Self.validate(release)
            try installer.install(release)
            AppLog.updates.notice("Updater launched pinned_version=\(version, privacy: .public)")
        } catch {
            let errorType = String(describing: type(of: error))
            AppLog.updates.error("Updater launch failed error_type=\(errorType, privacy: .public)")
            errorMessage = L10n.format(
                "The updater could not be launched: %@",
                error.localizedDescription
            )
        }
    }

    nonisolated static func validate(_ release: UpdateRelease) throws {
        guard !release.version.isEmpty else { throw UpdateError.invalidRelease }
        guard let archive = release.sourceArchiveURL,
              let checksum = release.sourceChecksumURL,
              isTrustedReleaseAsset(archive),
              isTrustedReleaseAsset(checksum) else {
            throw UpdateError.incompleteRelease
        }
    }

    private nonisolated static func isTrustedReleaseAsset(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/syb-illin/LogicLyrics/releases/download/")
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
