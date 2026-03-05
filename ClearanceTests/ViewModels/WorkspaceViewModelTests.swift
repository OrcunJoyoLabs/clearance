import XCTest
@testable import Clearance

@MainActor
final class WorkspaceViewModelTests: XCTestCase {
    func testOpenURLCreatesActiveSession() throws {
        let fileURL = try makeTempMarkdown(contents: "# One")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = RecentFilesStore(userDefaults: defaults, storageKey: "recent")
        let viewModel = WorkspaceViewModel(recentFilesStore: store)

        viewModel.open(url: fileURL)

        XCTAssertEqual(viewModel.activeSession?.url.path, fileURL.path)
    }

    func testOpenURLInsertsRecentAtTop() throws {
        let firstURL = try makeTempMarkdown(contents: "1")
        let secondURL = try makeTempMarkdown(contents: "2")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = RecentFilesStore(userDefaults: defaults, storageKey: "recent")
        let viewModel = WorkspaceViewModel(recentFilesStore: store)

        viewModel.open(url: firstURL)
        viewModel.open(url: secondURL)

        XCTAssertEqual(store.entries.first?.path, secondURL.path)
    }

    func testOpeningFromRecentEntryReopensSession() throws {
        let firstURL = try makeTempMarkdown(contents: "1")
        let secondURL = try makeTempMarkdown(contents: "2")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = RecentFilesStore(userDefaults: defaults, storageKey: "recent")
        let viewModel = WorkspaceViewModel(recentFilesStore: store)

        viewModel.open(url: firstURL)
        viewModel.open(url: secondURL)

        let firstEntry = store.entries.last!
        viewModel.open(recentEntry: firstEntry)

        XCTAssertEqual(viewModel.activeSession?.url.path, firstURL.path)
    }

    func testWindowTitleUpdatesForActiveAndDirtySession() throws {
        let fileURL = try makeTempMarkdown(contents: "# One")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = RecentFilesStore(userDefaults: defaults, storageKey: "recent")
        let viewModel = WorkspaceViewModel(recentFilesStore: store)

        viewModel.open(url: fileURL)
        XCTAssertEqual(viewModel.windowTitle, "sample.md")

        viewModel.activeSession?.content = "changed"
        let titleUpdate = expectation(description: "dirty title updates")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            titleUpdate.fulfill()
        }
        wait(for: [titleUpdate], timeout: 1.0)
        XCTAssertEqual(viewModel.windowTitle, "*sample.md")
    }

    func testExternalChangeFlowCanKeepCurrentVersion() throws {
        let fileURL = try makeTempMarkdown(contents: "# One")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = RecentFilesStore(userDefaults: defaults, storageKey: "recent")
        let viewModel = WorkspaceViewModel(recentFilesStore: store)
        viewModel.open(url: fileURL)

        try "outside change".write(to: fileURL, atomically: true, encoding: .utf8)
        viewModel.checkForExternalChangesNow()
        let alertUpdate = expectation(description: "external change alert updates")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            alertUpdate.fulfill()
        }
        wait(for: [alertUpdate], timeout: 1.0)
        XCTAssertEqual(viewModel.externalChangeDocumentName, "sample.md")

        viewModel.keepCurrentVersionAfterExternalChange()
        XCTAssertNil(viewModel.externalChangeDocumentName)
    }

    func testExternalChangeFlowCanReloadFromDisk() throws {
        let fileURL = try makeTempMarkdown(contents: "# One")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = RecentFilesStore(userDefaults: defaults, storageKey: "recent")
        let viewModel = WorkspaceViewModel(recentFilesStore: store)
        viewModel.open(url: fileURL)

        try "outside change".write(to: fileURL, atomically: true, encoding: .utf8)
        viewModel.checkForExternalChangesNow()

        viewModel.reloadActiveFromDisk()
        XCTAssertEqual(viewModel.activeSession?.content, "outside change")
        XCTAssertNil(viewModel.externalChangeDocumentName)
    }

    private func makeTempMarkdown(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("sample.md")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
