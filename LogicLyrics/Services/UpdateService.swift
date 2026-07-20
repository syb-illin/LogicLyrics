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
        checkTask = Task { [weak self] in
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
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                state = .idle
                if !silent { errorMessage = "Vérification impossible : \(error.localizedDescription)" }
            }
        }
    }

    func installAvailableUpdate() {
        guard case .available = state,
              let bundled = Bundle.main.url(forResource: "UPDATE", withExtension: "command") else {
            errorMessage = "Le programme de mise à jour est absent de l’application."
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
        } catch {
            errorMessage = "Le programme de mise à jour ne peut pas être lancé : \(error.localizedDescription)"
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
                "La release ne contient pas les deux fichiers de mise à jour attendus."
            case .unwritableInstallation:
                "L’app est installée dans un dossier non modifiable. Replace-la dans Téléchargements ou Applications avec les droits nécessaires."
            case .cannotLaunch:
                "macOS n’a pas pu ouvrir le programme de mise à jour dans Terminal."
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
