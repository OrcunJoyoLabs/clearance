import Foundation

struct WatchedFolderEntry: Codable, Identifiable, Equatable {
    let path: String
    let bookmarkData: Data
    let addedAt: Date

    var id: String { path }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Resolve the security-scoped bookmark back to a URL.
    /// Returns nil if the bookmark is stale or the volume is unmounted.
    func resolveBookmark() -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        return url
    }

    static func create(from url: URL) -> WatchedFolderEntry? {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return nil
        }

        return WatchedFolderEntry(
            path: url.standardizedFileURL.path,
            bookmarkData: bookmarkData,
            addedAt: .now
        )
    }
}
