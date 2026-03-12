import XCTest
@testable import Clearance

@MainActor
final class WatchedFolderStoreTests: XCTestCase {
    func testAddingFolderPersistsEntry() {
        let defaults = UserDefaults(suiteName: "WatchedFolderStoreTests-1")!
        defaults.removePersistentDomain(forName: "WatchedFolderStoreTests-1")
        let store = WatchedFolderStore(userDefaults: defaults)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let entry = WatchedFolderEntry(
            path: url.standardizedFileURL.path,
            bookmarkData: Data(),
            addedAt: .now
        )
        store.add(entry)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.path, url.standardizedFileURL.path)
    }

    func testRemovingFolderDeletesEntry() {
        let defaults = UserDefaults(suiteName: "WatchedFolderStoreTests-2")!
        defaults.removePersistentDomain(forName: "WatchedFolderStoreTests-2")
        let store = WatchedFolderStore(userDefaults: defaults)
        let entry = WatchedFolderEntry(path: "/tmp/project", bookmarkData: Data(), addedAt: .now)
        store.add(entry)

        store.remove(path: "/tmp/project")

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRoundTripsThroughUserDefaults() {
        let suite = "WatchedFolderStoreTests-3"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = WatchedFolderStore(userDefaults: defaults)
        first.add(WatchedFolderEntry(path: "/tmp/project", bookmarkData: Data([1, 2, 3]), addedAt: .now))

        let second = WatchedFolderStore(userDefaults: defaults)
        XCTAssertEqual(second.entries.count, 1)
        XCTAssertEqual(second.entries.first?.path, "/tmp/project")
        XCTAssertEqual(second.entries.first?.bookmarkData, Data([1, 2, 3]))
    }

    func testAddingDuplicatePathReplacesExisting() {
        let defaults = UserDefaults(suiteName: "WatchedFolderStoreTests-4")!
        defaults.removePersistentDomain(forName: "WatchedFolderStoreTests-4")
        let store = WatchedFolderStore(userDefaults: defaults)
        let first = WatchedFolderEntry(path: "/tmp/project", bookmarkData: Data([1]), addedAt: .distantPast)
        let second = WatchedFolderEntry(path: "/tmp/project", bookmarkData: Data([2]), addedAt: .now)

        store.add(first)
        store.add(second)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.bookmarkData, Data([2]))
    }

    func testContainsFolderPath() {
        let defaults = UserDefaults(suiteName: "WatchedFolderStoreTests-5")!
        defaults.removePersistentDomain(forName: "WatchedFolderStoreTests-5")
        let store = WatchedFolderStore(userDefaults: defaults)
        store.add(WatchedFolderEntry(path: "/tmp/project", bookmarkData: Data(), addedAt: .now))

        XCTAssertTrue(store.contains(path: "/tmp/project"))
        XCTAssertFalse(store.contains(path: "/tmp/other"))
    }

    func testDeepestMatchReturnsInnermost() {
        let defaults = UserDefaults(suiteName: "WatchedFolderStoreTests-6")!
        defaults.removePersistentDomain(forName: "WatchedFolderStoreTests-6")
        let store = WatchedFolderStore(userDefaults: defaults)
        store.add(WatchedFolderEntry(path: "/projects", bookmarkData: Data(), addedAt: .now))
        store.add(WatchedFolderEntry(path: "/projects/myapp", bookmarkData: Data(), addedAt: .now))

        let match = store.deepestMatch(for: "/projects/myapp/docs/README.md")

        XCTAssertEqual(match?.path, "/projects/myapp")
    }

    func testDeepestMatchReturnsNilForUnwatchedFile() {
        let defaults = UserDefaults(suiteName: "WatchedFolderStoreTests-7")!
        defaults.removePersistentDomain(forName: "WatchedFolderStoreTests-7")
        let store = WatchedFolderStore(userDefaults: defaults)
        store.add(WatchedFolderEntry(path: "/projects/myapp", bookmarkData: Data(), addedAt: .now))

        XCTAssertNil(store.deepestMatch(for: "/other/file.md"))
    }
}
