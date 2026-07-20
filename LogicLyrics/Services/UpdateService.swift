import AppKit
import Foundation

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
    private var checkTask: Task<Void, Never>?

    func check(silent: Bool = true) {
        guard state != .checking else { return }
        checkTask?.cancel()
        state = .checking
        let startedAt = Date()
        AppLog.updates.info("Update check started")
        checkTask = Task { [weak self, startedAt] in
            do {
                let url = URL(string: "https://api.github.com/repos/syb-illin/LogicLyrics/releases/latest")!
                var request = URLRequest(url: url)
                request.setValue("LogicLyrics-macOS", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task<Never, Never>.checkCancellation()
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let assetNames = Set(release.assets.map(\.name))
                guard assetNames.contains("LogicLyrics-macOS-source.zip"),
                      assetNames.contains("LogicLyrics-macOS-source.zip.sha256") else {
                    throw UpdateError.incompleteRelease
                }
                let remote = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                guard let self else { return }
                state = Self.isNewer(remote, than: Self.currentVersion)
                    ? .available(version: remote)
                    : .current
                let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                AppLog.updates.info("Update check succeeded duration_ms=\(durationMilliseconds, privacy: .public) remote_version=\(remote, privacy: .public)")
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

    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]
        struct Asset: Decodable { let name: String }
        enum CodingKeys: String, CodingKey { case tagName = "tag_name"; case assets }
    }

    private enum UpdateError: LocalizedError {
        case incompleteRelease
        case unwritableInstallation
        case cannotLaunch

        var errorDescription: String? {
            switch self {
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

    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }
}
