import Foundation

struct ProjectLocation: Equatable, Sendable {
    let url: URL
    let fileID: String?
    let bookmark: Data?
}

enum ProjectLocatorError: LocalizedError, Sendable {
    case unavailable
    case invalidProject

    var errorDescription: String? {
        switch self {
        case .unavailable:
            L10n.text("The Logic project could not be found. Choose its new location.")
        case .invalidProject:
            L10n.text("The selected item is not a readable .logicx project.")
        }
    }
}

protocol ProjectLocating {
    func capture(_ url: URL) -> ProjectLocation
    func resolve(path: String, bookmark: Data?) throws -> ProjectLocation
}

struct ProjectLocator: ProjectLocating {
    private let fileManager: FileManager
    private let bookmarks: any ProjectBookmarkManaging

    init(
        fileManager: FileManager = .default,
        bookmarks: any ProjectBookmarkManaging = FoundationProjectBookmarkManager()
    ) {
        self.fileManager = fileManager
        self.bookmarks = bookmarks
    }

    func capture(_ url: URL) -> ProjectLocation {
        let standardizedURL = url.standardizedFileURL
        let didAccess = standardizedURL.startAccessingSecurityScopedResource()
        defer { if didAccess { standardizedURL.stopAccessingSecurityScopedResource() } }
        let bookmark = bookmarks.create(for: standardizedURL, securityScoped: true)
            ?? bookmarks.create(for: standardizedURL, securityScoped: false)
        return ProjectLocation(
            url: standardizedURL,
            fileID: stableFileID(for: standardizedURL),
            bookmark: bookmark
        )
    }

    func resolve(path: String, bookmark: Data?) throws -> ProjectLocation {
        if let bookmark, let bookmarkedURL = resolveBookmark(bookmark), isLogicProject(bookmarkedURL) {
            return capture(bookmarkedURL)
        }

        let pathURL = URL(fileURLWithPath: path).standardizedFileURL
        guard isLogicProject(pathURL) else { throw ProjectLocatorError.unavailable }
        return capture(pathURL)
    }

    private func resolveBookmark(_ bookmark: Data) -> URL? {
        if let url = bookmarks.resolve(bookmark, securityScoped: true) {
            return url.standardizedFileURL
        }
        if let url = bookmarks.resolve(bookmark, securityScoped: false) {
            return url.standardizedFileURL
        }
        return nil
    }

    private func stableFileID(for url: URL) -> String? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let volume = attributes[.systemNumber] as? NSNumber,
              let file = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return String(format: "%llx:%llx", volume.uint64Value, file.uint64Value)
    }

    private func isLogicProject(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return url.pathExtension.lowercased() == "logicx"
            && fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
