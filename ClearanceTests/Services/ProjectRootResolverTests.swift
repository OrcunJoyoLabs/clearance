import XCTest
@testable import Clearance

@MainActor
final class ProjectRootResolverTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectRootResolverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    func testFindsGitRepoRoot() throws {
        let repoRoot = tempDir.appendingPathComponent("myrepo")
        let gitDir = repoRoot.appendingPathComponent(".git")
        let subDir = repoRoot.appendingPathComponent("src/components")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let filePath = subDir.appendingPathComponent("App.swift").path
        let result = ProjectRootResolver.projectRoot(for: filePath)

        XCTAssertEqual(result, repoRoot.path)
    }

    func testReturnsNilOutsideGitRepo() throws {
        let plainDir = tempDir.appendingPathComponent("norepo/sub")
        try FileManager.default.createDirectory(at: plainDir, withIntermediateDirectories: true)

        let filePath = plainDir.appendingPathComponent("file.md").path
        let result = ProjectRootResolver.projectRoot(for: filePath)

        XCTAssertNil(result)
    }

    func testNestedDirectoriesResolveToSameRoot() throws {
        let repoRoot = tempDir.appendingPathComponent("project")
        let gitDir = repoRoot.appendingPathComponent(".git")
        let dirA = repoRoot.appendingPathComponent("docs")
        let dirB = repoRoot.appendingPathComponent("tools/scripts")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)

        let fileA = dirA.appendingPathComponent("readme.md").path
        let fileB = dirB.appendingPathComponent("build.sh").path

        let rootA = ProjectRootResolver.projectRoot(for: fileA)
        let rootB = ProjectRootResolver.projectRoot(for: fileB)

        XCTAssertEqual(rootA, repoRoot.path)
        XCTAssertEqual(rootA, rootB)
    }
}
