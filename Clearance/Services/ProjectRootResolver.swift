import Foundation

@MainActor
enum ProjectRootResolver {
    // nil value = "no project root found"; missing key = "not yet resolved"
    private static var cache: [String: String?] = [:]

    static func projectRoot(for filePath: String) -> String? {
        guard filePath.hasPrefix("/") else { return nil }
        let dir = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        if let cached = cache[dir] {
            return cached
        }
        let result = resolve(startingAt: dir)
        cache[dir] = result
        return result
    }

    private static func resolve(startingAt dir: String) -> String? {
        var url = URL(fileURLWithPath: dir)
        // Stop before root to avoid collapsing all files into one group
        // if /.git somehow exists.
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url.path
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }
}
