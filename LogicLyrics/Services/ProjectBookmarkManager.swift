import Foundation

protocol ProjectBookmarkManaging: Sendable {
    func create(for url: URL, securityScoped: Bool) -> Data?
    func resolve(_ data: Data, securityScoped: Bool) -> URL?
}

struct FoundationProjectBookmarkManager: ProjectBookmarkManaging {
    func create(for url: URL, securityScoped: Bool) -> Data? {
        try? url.bookmarkData(
            options: securityScoped ? [.withSecurityScope] : [],
            includingResourceValuesForKeys: [.fileResourceIdentifierKey],
            relativeTo: nil
        )
    }

    func resolve(_ data: Data, securityScoped: Bool) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: securityScoped ? [.withSecurityScope, .withoutUI] : [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
