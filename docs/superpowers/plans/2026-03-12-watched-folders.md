# Watched Folders Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace one-shot folder import with persistent watched folders that auto-discover recently-modified markdown files in project directories.

**Architecture:** New `WatchedFolderStore` manages persisted folder bookmarks. A `WatchedFolderScanner` handles filesystem enumeration with junk-directory pruning and 7-day recency filter. The sidebar's folder-grouped view merges scanned files with manually-opened files, with per-group refresh buttons. A `SidebarItem` enum unifies the two file sources.

**Tech Stack:** Swift 6.0, SwiftUI, macOS 14.0+, UserDefaults persistence, security-scoped bookmarks.

**Spec:** `docs/superpowers/specs/2026-03-12-watched-folders-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `Clearance/Models/WatchedFolderEntry.swift` | Data model for a watched folder (path, bookmark, date) |
| Create | `Clearance/Models/WatchedFolderStore.swift` | Persistence layer for watched folders (add/remove/restore) |
| Create | `Clearance/Services/WatchedFolderScanner.swift` | Filesystem scanning with junk-dir pruning + 7-day filter |
| Create | `Clearance/Models/SidebarItem.swift` | Enum unifying RecentFileEntry and scanned files |
| Modify | `Clearance/ViewModels/WorkspaceViewModel.swift` | Replace folder import with watched folder registration + scan |
| Modify | `Clearance/Views/Sidebar/RecentFilesSidebar.swift` | Merge scanned files into folder-grouped view, add refresh + context menu |
| Modify | `Clearance/Views/WorkspaceView.swift` | Remove folder import dialog, wire up new callbacks |
| Modify | `Clearance/Models/RecentFilesStore.swift` | Remove `add(urls:)` |
| Create | `ClearanceTests/Models/WatchedFolderStoreTests.swift` | Tests for store CRUD + persistence |
| Create | `ClearanceTests/Services/WatchedFolderScannerTests.swift` | Tests for scanning logic |
| Modify | `ClearanceTests/ViewModels/WorkspaceViewModelTests.swift` | Replace folder import tests with watched folder tests |
| Modify | `ClearanceTests/Models/RecentFilesStoreTests.swift` | Remove bulk add tests if any |

---

## Chunk 1: Data Model + Store + Scanner

### Task 1: WatchedFolderEntry model

**Files:**
- Create: `Clearance/Models/WatchedFolderEntry.swift`

- [ ] **Step 1: Create model file**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Clearance/Models/WatchedFolderEntry.swift
git commit -m "feat: add WatchedFolderEntry model with security-scoped bookmark support"
```

---

### Task 2: WatchedFolderStore with tests

**Files:**
- Create: `Clearance/Models/WatchedFolderStore.swift`
- Create: `ClearanceTests/Models/WatchedFolderStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Clearance -destination 'platform=macOS' -only-testing ClearanceTests/WatchedFolderStoreTests 2>&1 | tail -20`
Expected: Compilation error — `WatchedFolderStore` not found.

- [ ] **Step 3: Implement WatchedFolderStore**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clearance -destination 'platform=macOS' -only-testing ClearanceTests/WatchedFolderStoreTests 2>&1 | tail -20`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Clearance/Models/WatchedFolderStore.swift ClearanceTests/Models/WatchedFolderStoreTests.swift
git commit -m "feat: add WatchedFolderStore with persistence and deepest-match lookup"
```

---

### Task 3: WatchedFolderScanner with tests

**Files:**
- Create: `Clearance/Services/WatchedFolderScanner.swift`
- Create: `ClearanceTests/Services/WatchedFolderScannerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Clearance

final class WatchedFolderScannerTests: XCTestCase {
    func testFindsRecentMarkdownFiles() throws {
        let folder = try makeTempFolder()
        let recentFile = folder.appendingPathComponent("notes.md")
        try "# Notes".write(to: recentFile, atomically: true, encoding: .utf8)

        let results = WatchedFolderScanner.scan(directory: folder)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.url.lastPathComponent, "notes.md")
    }

    func testExcludesFilesOlderThanSevenDays() throws {
        let folder = try makeTempFolder()
        let oldFile = folder.appendingPathComponent("old.md")
        try "# Old".write(to: oldFile, atomically: true, encoding: .utf8)
        let eightDaysAgo = Calendar.current.date(byAdding: .day, value: -8, to: .now)!
        try FileManager.default.setAttributes(
            [.modificationDate: eightDaysAgo],
            ofItemAtPath: oldFile.path
        )

        let results = WatchedFolderScanner.scan(directory: folder)

        XCTAssertTrue(results.isEmpty)
    }

    func testSkipsJunkDirectories() throws {
        let folder = try makeTempFolder()
        let nodeModules = folder.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try "# Junk".write(
            to: nodeModules.appendingPathComponent("readme.md"),
            atomically: true,
            encoding: .utf8
        )
        let src = folder.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "# Good".write(
            to: src.appendingPathComponent("notes.md"),
            atomically: true,
            encoding: .utf8
        )

        let results = WatchedFolderScanner.scan(directory: folder)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.url.lastPathComponent, "notes.md")
    }

    func testFindsFilesInSubdirectories() throws {
        let folder = try makeTempFolder()
        let deep = folder
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("specs", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try "# Deep".write(
            to: deep.appendingPathComponent("spec.md"),
            atomically: true,
            encoding: .utf8
        )

        let results = WatchedFolderScanner.scan(directory: folder)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.url.lastPathComponent, "spec.md")
    }

    func testSortsNewestFirst() throws {
        let folder = try makeTempFolder()
        let older = folder.appendingPathComponent("older.md")
        let newer = folder.appendingPathComponent("newer.md")
        try "# Older".write(to: older, atomically: true, encoding: .utf8)
        try "# Newer".write(to: newer, atomically: true, encoding: .utf8)
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        try FileManager.default.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: older.path)

        let results = WatchedFolderScanner.scan(directory: folder)

        XCTAssertEqual(results.first?.url.lastPathComponent, "newer.md")
        XCTAssertEqual(results.last?.url.lastPathComponent, "older.md")
    }

    func testReturnsEmptyForMissingDirectory() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let results = WatchedFolderScanner.scan(directory: missing)

        XCTAssertTrue(results.isEmpty)
    }

    func testSupportsAllExtensions() throws {
        let folder = try makeTempFolder()
        try "md".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "markdown".write(to: folder.appendingPathComponent("b.markdown"), atomically: true, encoding: .utf8)
        try "txt".write(to: folder.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        try "swift".write(to: folder.appendingPathComponent("d.swift"), atomically: true, encoding: .utf8)

        let results = WatchedFolderScanner.scan(directory: folder)

        XCTAssertEqual(results.count, 3)
    }

    private func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Clearance -destination 'platform=macOS' -only-testing ClearanceTests/WatchedFolderScannerTests 2>&1 | tail -20`
Expected: Compilation error — `WatchedFolderScanner` not found.

- [ ] **Step 3: Implement WatchedFolderScanner**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Clearance -destination 'platform=macOS' -only-testing ClearanceTests/WatchedFolderScannerTests 2>&1 | tail -20`
Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Clearance/Services/WatchedFolderScanner.swift ClearanceTests/Services/WatchedFolderScannerTests.swift
git commit -m "feat: add WatchedFolderScanner with junk-directory pruning and 7-day filter"
```

---

### Task 4: SidebarItem model

**Files:**
- Create: `Clearance/Models/SidebarItem.swift`

- [ ] **Step 1: Create SidebarItem**

```swift
import Foundation

enum SidebarItem: Identifiable, Equatable {
    case recentEntry(RecentFileEntry)
    case scannedFile(url: URL, modificationDate: Date)

    var id: String { path }

    var path: String {
        switch self {
        case .recentEntry(let entry):
            return entry.path
        case .scannedFile(let url, _):
            return url.standardizedFileURL.path
        }
    }

    var displayName: String {
        switch self {
        case .recentEntry(let entry):
            return entry.displayName
        case .scannedFile(let url, _):
            return url.lastPathComponent
        }
    }

    var sortDate: Date {
        switch self {
        case .recentEntry(let entry):
            return entry.lastOpenedAt
        case .scannedFile(_, let modDate):
            return modDate
        }
    }

    var fileURL: URL {
        switch self {
        case .recentEntry(let entry):
            return entry.fileURL
        case .scannedFile(let url, _):
            return url
        }
    }

    var isScannedOnly: Bool {
        switch self {
        case .recentEntry:
            return false
        case .scannedFile:
            return true
        }
    }

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        lhs.path == rhs.path
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Clearance/Models/SidebarItem.swift
git commit -m "feat: add SidebarItem enum unifying recent entries and scanned files"
```

---

## Chunk 2: ViewModel + Sidebar Integration

### Task 5: Replace folder import in WorkspaceViewModel

**Files:**
- Modify: `Clearance/ViewModels/WorkspaceViewModel.swift`
- Modify: `ClearanceTests/ViewModels/WorkspaceViewModelTests.swift`

- [ ] **Step 1: Update WorkspaceViewModel**

Key changes to `WorkspaceViewModel.swift`:

1. Add `watchedFolderStore` property (injected via init, like `recentFilesStore`):
```swift
let watchedFolderStore: WatchedFolderStore
```

2. Add `@Published var scannedFiles: [String: [ScannedFile]] = [:]` — keyed by watched folder path.

3. Remove: `pendingFolderImport` published property, `PendingFolderImport` struct (top of file), `folderImportConfirmationThreshold`, `queueOrImportFolder(at:)`, `importFolderURLs(_:)`, `confirmPendingFolderImport()`, `cancelPendingFolderImport()`.

4. Replace `openPickedItem` folder branch:
```swift
@discardableResult
func openPickedItem(_ url: URL) -> DocumentSession? {
    if isDirectory(url) {
        return addWatchedFolder(url: url)
    }
    return open(url: url)
}

private func addWatchedFolder(url: URL) -> DocumentSession? {
    guard let entry = WatchedFolderEntry.create(from: url) else {
        errorMessage = "Could not bookmark folder: \(url.path)"
        return nil
    }
    watchedFolderStore.add(entry)
    refreshWatchedFolder(path: entry.path)
    guard let newest = scannedFiles[entry.path]?.first else {
        return nil
    }
    return open(url: newest.url)
}
```

5. Add refresh methods:
```swift
func refreshWatchedFolder(path: String) {
    guard let entry = watchedFolderStore.entries.first(where: { $0.path == path }) else {
        return
    }
    let folderURL: URL
    if let resolved = entry.resolveBookmark() {
        folderURL = resolved
    } else {
        folderURL = URL(fileURLWithPath: entry.path)
    }
    let accessed = folderURL.startAccessingSecurityScopedResource()
    defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }
    scannedFiles[path] = WatchedFolderScanner.scan(directory: folderURL)
}

func refreshAllWatchedFolders() {
    for entry in watchedFolderStore.entries {
        refreshWatchedFolder(path: entry.path)
    }
}

func removeWatchedFolder(path: String) {
    watchedFolderStore.remove(path: path)
    scannedFiles.removeValue(forKey: path)
}
```

6. Update `init` to accept `watchedFolderStore` and call `refreshAllWatchedFolders()`:
```swift
init(
    recentFilesStore: RecentFilesStore = RecentFilesStore(),
    watchedFolderStore: WatchedFolderStore = WatchedFolderStore(),
    openPanelService: OpenPanelServicing = OpenPanelService(),
    appSettings: AppSettings = AppSettings(),
    remoteDocumentLoader: ...
) {
    self.recentFilesStore = recentFilesStore
    self.watchedFolderStore = watchedFolderStore
    // ... rest unchanged
    super.init()
    refreshAllWatchedFolders()
}
```

- [ ] **Step 2: Update tests — remove old folder import tests, add watched folder tests**

Remove: `testOpeningFolderImportsFilesImmediatelyWhenCountIsTenOrLess`, `testOpeningFolderQueuesConfirmationWhenCountExceedsTen`, `testConfirmingPendingFolderImportAddsNewestFilesToTopOfHistory`.

**Important:** Update ALL existing tests that create `WorkspaceViewModel` to also pass a test-specific `WatchedFolderStore` to prevent cross-test contamination from `.standard` UserDefaults. For each existing test, add:
```swift
let watchedStore = WatchedFolderStore(userDefaults: defaults, storageKey: "watched")
```
And pass it to the ViewModel init: `WorkspaceViewModel(recentFilesStore: store, watchedFolderStore: watchedStore, ...)`. The helpers `makeTempFolderWithFiles` and `setModificationDate` already exist in the test file — reuse them.

Add new tests:

```swift
func testOpeningFolderRegistersWatchedFolder() throws {
    let folderURL = try makeTempFolderWithFiles(["notes.md"])
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = RecentFilesStore(userDefaults: defaults, storageKey: "recent")
    let watchedStore = WatchedFolderStore(userDefaults: defaults, storageKey: "watched")
    let viewModel = WorkspaceViewModel(
        recentFilesStore: store,
        watchedFolderStore: watchedStore,
        openPanelService: MockOpenPanelService(openItemURL: folderURL)
    )

    let session = viewModel.promptAndOpenFile()

    XCTAssertNotNil(session)
    XCTAssertEqual(session?.url.lastPathComponent, "notes.md")
    XCTAssertTrue(watchedStore.contains(path: folderURL.standardizedFileURL.path))
}

func testOpeningFolderOpensNewestFile() throws {
    let folderURL = try makeTempFolderWithFiles(["old.md", "new.md"])
    let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
    try setModificationDate(twoDaysAgo, for: folderURL.appendingPathComponent("old.md"))
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = RecentFilesStore(userDefaults: defaults, storageKey: "recent")
    let watchedStore = WatchedFolderStore(userDefaults: defaults, storageKey: "watched")
    let viewModel = WorkspaceViewModel(
        recentFilesStore: store,
        watchedFolderStore: watchedStore,
        openPanelService: MockOpenPanelService(openItemURL: folderURL)
    )

    let session = viewModel.promptAndOpenFile()

    XCTAssertEqual(session?.url.lastPathComponent, "new.md")
}

func testRefreshWatchedFolderPicksUpNewFiles() throws {
    let folderURL = try makeTempFolderWithFiles(["initial.md"])
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = RecentFilesStore(userDefaults: defaults, storageKey: "recent")
    let watchedStore = WatchedFolderStore(userDefaults: defaults, storageKey: "watched")
    let viewModel = WorkspaceViewModel(
        recentFilesStore: store,
        watchedFolderStore: watchedStore,
        openPanelService: MockOpenPanelService(openItemURL: folderURL)
    )

    _ = viewModel.promptAndOpenFile()
    let path = folderURL.standardizedFileURL.path

    // Add a new file
    try "# New".write(
        to: folderURL.appendingPathComponent("added.md"),
        atomically: true,
        encoding: .utf8
    )

    viewModel.refreshWatchedFolder(path: path)

    XCTAssertEqual(viewModel.scannedFiles[path]?.count, 2)
}

func testRemoveWatchedFolderCleansUpScanResults() throws {
    let folderURL = try makeTempFolderWithFiles(["notes.md"])
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = RecentFilesStore(userDefaults: defaults, storageKey: "recent")
    let watchedStore = WatchedFolderStore(userDefaults: defaults, storageKey: "watched")
    let viewModel = WorkspaceViewModel(
        recentFilesStore: store,
        watchedFolderStore: watchedStore,
        openPanelService: MockOpenPanelService(openItemURL: folderURL)
    )

    _ = viewModel.promptAndOpenFile()
    let path = folderURL.standardizedFileURL.path
    XCTAssertTrue(watchedStore.contains(path: path))

    viewModel.removeWatchedFolder(path: path)

    XCTAssertFalse(watchedStore.contains(path: path))
    XCTAssertNil(viewModel.scannedFiles[path])
}
```

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -scheme Clearance -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add Clearance/ViewModels/WorkspaceViewModel.swift ClearanceTests/ViewModels/WorkspaceViewModelTests.swift
git commit -m "feat: replace folder import with watched folder registration and scanning"
```

---

### Task 6: Update RecentFilesSidebar for watched folders

**Files:**
- Modify: `Clearance/Views/Sidebar/RecentFilesSidebar.swift`
- Modify: `Clearance/Views/WorkspaceView.swift`

This is the most complex task. It changes the sidebar's data model and adds new UI interactions. Work through each step carefully.

- [ ] **Step 1: Change `RecentFilesSection` to use `SidebarItem`**

Replace the private `RecentFilesSection` struct at the bottom of `RecentFilesSidebar.swift`:

```swift
private struct RecentFilesSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let entries: [SidebarItem]
    let isWatchedFolder: Bool

    init(bucket: RecentFileBucket, entries: [RecentFileEntry]) {
        self.id = bucket.rawValue
        self.title = bucket.rawValue
        self.subtitle = nil
        self.entries = entries.map { .recentEntry($0) }
        self.isWatchedFolder = false
    }

    init(id: String, title: String, subtitle: String?, entries: [SidebarItem], isWatchedFolder: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.entries = entries
        self.isWatchedFolder = isWatchedFolder
    }
}
```

- [ ] **Step 2: Add new props to RecentFilesSidebar and change callbacks to use SidebarItem**

Update the struct properties:
```swift
struct RecentFilesSidebar: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let entries: [RecentFileEntry]
    @Binding var selectedPath: String?
    @Binding var sidebarGrouping: SidebarGrouping
    let watchedFolders: [WatchedFolderEntry]
    let scannedFiles: [String: [ScannedFile]]
    let onOpenFile: () -> Void
    let onDropURL: (URL) -> Bool
    let onSelect: (SidebarItem) -> Void
    let onOpenInNewWindow: (SidebarItem) -> Void
    let onRemoveFromSidebar: (SidebarItem) -> Void
    let onRefreshWatchedFolder: (String) -> Void
    let onRemoveWatchedFolder: (String) -> Void

    @State private var expandedSections: [String: Bool] = [:]
```

- [ ] **Step 3: Update the List body to use SidebarItem**

Replace the `List` content in `body`:
```swift
List(selection: $selectedPath) {
    ForEach(groupedEntries) { section in
        Section(isExpanded: sectionBinding(for: section.id)) {
            ForEach(section.entries) { item in
                row(for: item, showDirectory: sidebarGrouping != .byFolder)
            }
        } header: {
            sectionHeader(for: section)
        }
    }
}
.contextMenu(forSelectionType: String.self) { selectedPaths in
    if let path = selectedPaths.first,
       let item = findItem(byPath: path) {
        contextMenuActions(for: item)
    }
}
.onChange(of: selectedPath) { _, newPath in
    guard let newPath,
          let item = findItem(byPath: newPath) else {
        return
    }
    onSelect(item)
}
```

Add a helper to find items across all sections:
```swift
private func findItem(byPath path: String) -> SidebarItem? {
    for section in groupedEntries {
        if let item = section.entries.first(where: { $0.path == path }) {
            return item
        }
    }
    return nil
}
```

- [ ] **Step 4: Create section header view with refresh button**

```swift
@ViewBuilder
private func sectionHeader(for section: RecentFilesSection) -> some View {
    HStack {
        if let subtitle = section.subtitle {
            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text(section.title)
        }

        if section.isWatchedFolder {
            Spacer()
            Button {
                onRefreshWatchedFolder(section.id)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Refresh")
        }
    }
    .contextMenu {
        if section.isWatchedFolder {
            Button("Stop Watching Folder") {
                onRemoveWatchedFolder(section.id)
            }
        }
    }
}
```

- [ ] **Step 5: Rewrite `entriesGroupedByFolder` to merge watched folder data**

```swift
private var entriesGroupedByFolder: [RecentFilesSection] {
    let watchedPaths = Set(watchedFolders.map(\.path))
    var claimedPaths: Set<String> = []
    var sections: [RecentFilesSection] = []

    // 1. Build watched folder sections
    for folder in watchedFolders {
        var items: [SidebarItem] = []
        var seenPaths: Set<String> = []

        // Add manually-opened files under this watched folder
        for entry in entries where entry.fileURL.isFileURL {
            if entry.path.hasPrefix(folder.path + "/") {
                items.append(.recentEntry(entry))
                seenPaths.insert(entry.path)
                claimedPaths.insert(entry.path)
            }
        }

        // Add scanned files not already covered by recent entries
        if let scanned = scannedFiles[folder.path] {
            for file in scanned {
                let filePath = file.url.standardizedFileURL.path
                if !seenPaths.contains(filePath) {
                    items.append(.scannedFile(url: file.url, modificationDate: file.modificationDate))
                    seenPaths.insert(filePath)
                }
            }
        }

        items.sort { $0.sortDate > $1.sortDate }

        let components = folder.path.split(separator: "/")
        let displayName = components.last.map(String.init) ?? folder.path

        sections.append(RecentFilesSection(
            id: folder.path,
            title: displayName,
            subtitle: folder.path,
            entries: items,
            isWatchedFolder: true
        ))
    }

    // 2. Group remaining entries by project root (existing logic)
    var folderOrder: [String] = []
    var folderEntries: [String: [SidebarItem]] = [:]

    for entry in entries {
        guard !claimedPaths.contains(entry.path) else { continue }

        let key: String
        if entry.fileURL.isFileURL, let projectRoot = ProjectRootResolver.projectRoot(for: entry.path) {
            // Skip if this project root is itself a watched folder
            if watchedPaths.contains(projectRoot) { continue }
            key = projectRoot
        } else {
            key = Self.otherKey
        }

        if folderEntries[key] == nil {
            folderOrder.append(key)
        }
        folderEntries[key, default: []].append(.recentEntry(entry))
    }

    for folder in folderOrder {
        guard let sectionEntries = folderEntries[folder], !sectionEntries.isEmpty else { continue }

        if folder == Self.otherKey {
            sections.append(RecentFilesSection(
                id: Self.otherKey,
                title: "Other",
                subtitle: nil,
                entries: sectionEntries
            ))
        } else {
            let components = folder.split(separator: "/")
            let displayName = components.last.map(String.init) ?? folder
            sections.append(RecentFilesSection(
                id: folder,
                title: displayName,
                subtitle: folder,
                entries: sectionEntries
            ))
        }
    }

    return sections
}
```

- [ ] **Step 6: Update `entriesGroupedByDate` — exclude scan-only files**

The date-grouped view only shows `RecentFileEntry` items (no scanned files). Update to return `[SidebarItem]`:
```swift
private var entriesGroupedByDate: [RecentFilesSection] {
    var buckets: [RecentFileBucket: [RecentFileEntry]] = [:]
    for entry in entries {
        buckets[RecentFileBucket.bucket(for: entry.lastOpenedAt), default: []].append(entry)
    }

    return RecentFileBucket.allCases.compactMap { bucket in
        guard let sectionEntries = buckets[bucket], !sectionEntries.isEmpty else {
            return nil
        }
        return RecentFilesSection(bucket: bucket, entries: sectionEntries)
    }
}
```
This is unchanged from the original — it already excludes scanned files because it only iterates `entries` (which is `[RecentFileEntry]`). The `RecentFilesSection(bucket:entries:)` init wraps them in `.recentEntry()`.

- [ ] **Step 7: Update `row(for:)` to accept SidebarItem**

```swift
private func row(for item: SidebarItem, showDirectory: Bool = true) -> some View {
    HStack(alignment: .top, spacing: 8) {
        Image(systemName: item.isScannedOnly ? "doc.text.magnifyingglass" : (item.fileURL.isFileURL ? "doc.text" : "globe"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 14, alignment: .leading)

        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayName)
                .font(.body)
                .lineLimit(1)
            if showDirectory {
                Text(item.fileURL.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .tag(item.path)
    .contextMenu {
        contextMenuActions(for: item)
    }
    .draggable(item.path)
}
```

- [ ] **Step 8: Update `contextMenuActions` to accept SidebarItem**

```swift
@ViewBuilder
private func contextMenuActions(for item: SidebarItem) -> some View {
    if item.fileURL.isFileURL {
        Button("Open In New Window") {
            selectedPath = item.path
            onOpenInNewWindow(item)
        }

        Divider()

        Button("Reveal in Finder") {
            selectedPath = item.path
            NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
        }

        Button("Copy Path to File") {
            selectedPath = item.path
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(item.path, forType: .string)
        }

        Divider()

        if !item.isScannedOnly {
            Button("Remove from History") {
                selectedPath = item.path
                onRemoveFromSidebar(item)
            }
        }
    } else {
        Button("Copy URL") {
            selectedPath = item.path
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(item.fileURL.absoluteString, forType: .string)
        }

        Divider()

        Button("Remove from History") {
            selectedPath = item.path
            onRemoveFromSidebar(item)
        }
    }
}
```

- [ ] **Step 9: Update animation value**

Change the `animation` value to use `SidebarItem`:
```swift
.animation(
    accessibilityReduceMotion ? nil : .snappy(duration: 0.26),
    value: groupedEntries.flatMap { $0.entries.map { "\($0.path)|\($0.sortDate.timeIntervalSinceReferenceDate)" } }
)
```

- [ ] **Step 10: Update WorkspaceView callbacks**

In `WorkspaceView.swift`, update the `RecentFilesSidebar` call site to match the new API:

```swift
RecentFilesSidebar(
    entries: viewModel.recentFilesStore.entries,
    selectedPath: $viewModel.selectedRecentPath,
    sidebarGrouping: $appSettings.sidebarGrouping,
    watchedFolders: viewModel.watchedFolderStore.entries,
    scannedFiles: viewModel.scannedFiles,
    onOpenFile: { openDocumentFromPicker() },
    onDropURL: { handleSidebarDrop($0) }
) { item in
    selectSidebarItem(item)
} onOpenInNewWindow: { item in
    popOutSidebarItem(item)
} onRemoveFromSidebar: { item in
    removeSidebarItem(item)
} onRefreshWatchedFolder: { path in
    viewModel.refreshWatchedFolder(path: path)
} onRemoveWatchedFolder: { path in
    viewModel.removeWatchedFolder(path: path)
}
```

Add helper methods in `WorkspaceView`:
```swift
private func selectSidebarItem(_ item: SidebarItem) {
    switch item {
    case .recentEntry(let entry):
        selectRecentEntry(entry)
    case .scannedFile(let url, _):
        _ = openDocument(url)
    }
}

private func popOutSidebarItem(_ item: SidebarItem) {
    switch item {
    case .recentEntry(let entry):
        popOut(entry: entry)
    case .scannedFile(let url, _):
        if let session = popOutSession(for: url) {
            popoutWindowController.openWindow(
                for: session,
                mode: viewModel.mode,
                appSettings: appSettings
            )
        }
    }
}

private func removeSidebarItem(_ item: SidebarItem) {
    switch item {
    case .recentEntry(let entry):
        removeRecentEntry(entry)
    case .scannedFile:
        break // scan-only files can't be removed from history
    }
}
```

Remove the folder import confirmation alert:
```swift
// DELETE this entire .alert block:
.alert(
    "Add \(viewModel.pendingFolderImport?.urls.count ?? 0) Files To History?",
    ...
)
```

- [ ] **Step 11: Run all tests and verify build**

Run: `xcodebuild test -scheme Clearance -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 12: Commit**

```bash
git add Clearance/Views/Sidebar/RecentFilesSidebar.swift Clearance/Views/WorkspaceView.swift
git commit -m "feat: integrate watched folders into sidebar with refresh and stop-watching"
```

---

### Task 7: Remove dead code from RecentFilesStore

**Files:**
- Modify: `Clearance/Models/RecentFilesStore.swift`
- Modify: `ClearanceTests/Models/RecentFilesStoreTests.swift` (if bulk add tests exist)

- [ ] **Step 1: Remove `add(urls:)` from RecentFilesStore**

Delete the `add(urls:)` method (lines 35-54 of `RecentFilesStore.swift`).

- [ ] **Step 2: Run all tests**

Run: `xcodebuild test -scheme Clearance -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All tests pass (no remaining callers of `add(urls:)`).

- [ ] **Step 3: Commit**

```bash
git add Clearance/Models/RecentFilesStore.swift
git commit -m "chore: remove dead add(urls:) bulk import method from RecentFilesStore"
```

---

### Task 8: Final integration test — build and manual verification

- [ ] **Step 1: Run full test suite**

Run: `xcodebuild test -scheme Clearance -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 2: Build and launch**

```bash
xcodebuild -scheme Clearance -configuration Debug -derivedDataPath build/ build 2>&1 | tail -5
open build/Build/Products/Debug/Clearance.app
```

- [ ] **Step 3: Manual verification checklist**

1. Open a project folder — verify it appears as a watched folder section in "Group by Folder" view
2. Verify only recent (.md) files are shown
3. Click refresh — verify new files appear
4. Click a scanned file — verify it opens and gets added to history
5. Right-click section header — verify "Stop Watching Folder" appears and works
6. Quit and relaunch — verify watched folders persist and auto-scan on launch
7. Switch to "Group by Date" — verify scan-only files don't appear
