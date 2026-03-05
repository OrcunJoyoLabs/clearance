import XCTest
@testable import Clearance

final class EditorTemplateTests: XCTestCase {
    func testEditorTemplateContainsCodeMirrorBootstrap() {
        let html = EditorTemplateProvider().html()

        XCTAssertTrue(html.contains("CodeMirror.fromTextArea"))
        XCTAssertTrue(html.contains("mode: 'markdown'"))
        XCTAssertTrue(html.contains("undoDepth: 10000"))
    }
}
