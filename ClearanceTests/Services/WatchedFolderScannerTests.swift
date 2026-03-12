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
