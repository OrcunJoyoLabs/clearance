import Foundation

final class WatchedFolderStore: ObservableObject {
    @Published private(set) var entries: [WatchedFolderEntry]

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(userDefaults: UserDefaults = .standard, storageKey: String = "watchedFolders") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey

        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([WatchedFolderEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    func add(_ entry: WatchedFolderEntry) {
        entries.removeAll { $0.path == entry.path }
        entries.append(entry)
        persist()
    }

    func remove(path: String) {
        let priorCount = entries.count
        entries.removeAll { $0.path == path }
        guard entries.count != priorCount else { return }
        persist()
    }

    func contains(path: String) -> Bool {
        entries.contains { $0.path == path }
    }

    /// Returns the deepest (most specific) watched folder that contains the given file path.
    func deepestMatch(for filePath: String) -> WatchedFolderEntry? {
        entries
            .filter { filePath.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
