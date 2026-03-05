import XCTest
@testable import Clearance

final class RenderedHTMLBuilderTests: XCTestCase {
    func testIncludesFrontmatterRowsForFlattenedKeys() {
        let document = ParsedMarkdownDocument(
            body: "# Title",
            flattenedFrontmatter: [
                "title": "Doc",
                "seo.keywords[0]": "alpha"
            ]
        )

        let html = RenderedHTMLBuilder().build(document: document)

        XCTAssertTrue(html.contains("<th>title</th>"))
        XCTAssertTrue(html.contains("<td>Doc</td>"))
        XCTAssertTrue(html.contains("<th>seo.keywords[0]</th>"))
    }

    func testIncludesRenderedMarkdownBodyHTML() {
        let document = ParsedMarkdownDocument(body: "# Heading", flattenedFrontmatter: [:])

        let html = RenderedHTMLBuilder().build(document: document)

        XCTAssertTrue(html.contains("<h1>Heading</h1>"))
    }

    func testIncludesLocalOnlyContentSecurityPolicy() {
        let document = ParsedMarkdownDocument(body: "Hello", flattenedFrontmatter: [:])

        let html = RenderedHTMLBuilder().build(document: document)

        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("img-src data: file:"))
    }

    func testHighlightsFencedCodeBlocksWithoutNetworkDependencies() {
        let document = ParsedMarkdownDocument(body: "```swift\nlet value = 1\n```", flattenedFrontmatter: [:])

        let html = RenderedHTMLBuilder().build(document: document)

        XCTAssertTrue(html.contains("hl-keyword"))
        XCTAssertTrue(html.contains("hl-number"))
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("script-src"))
    }
}
