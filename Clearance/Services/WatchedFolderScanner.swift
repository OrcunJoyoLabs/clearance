import Foundation

struct ScannedFile {
    let url: URL
    let modificationDate: Date
}

enum WatchedFolderScanner {
    private static let supportedExtensions: Set<String> = ["md", "markdown", "txt"]

    private static let skippedDirectoryNames: Set<String> = [
        "node_modules", "build", "dist", ".build", "DerivedData",
        "Pods", "vendor", ".venv", "__pycache__", "target",
        ".gradle", ".next", ".nuxt"
    ]

    static func scan(directory: URL, recencyDays: Int = 7) -> [ScannedFile] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -recencyDays, to: .now) ?? .distantPast

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [ScannedFile] = []

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .contentModificationDateKey]
            ) else {
                continue
            }

            if values.isDirectory == true {
                if skippedDirectoryNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }

            let modDate = values.contentModificationDate ?? .distantPast
            guard modDate >= cutoffDate else {
                continue
            }

            results.append(ScannedFile(url: url, modificationDate: modDate))
        }

        return results.sorted {
            if $0.modificationDate == $1.modificationDate {
                return $0.url.path < $1.url.path
            }
            return $0.modificationDate > $1.modificationDate
        }
    }
}
