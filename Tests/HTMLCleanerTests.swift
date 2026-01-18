import XCTest
@testable import MegaplanHepler

/// Unit tests for HTMLCleaner
/// Critical: Tests for XSS protection via HTML entity decoding order
final class HTMLCleanerTests: XCTestCase {

    // MARK: - XSS Protection Tests (Critical)

    /// Test that &amp; is decoded LAST to prevent XSS via double encoding
    /// Attack vector: "&amp;lt;script&amp;gt;" should NOT become "<script>"
    func testHTMLEntityDecodingOrder_PreventXSS() {
        let input = "&amp;lt;script&amp;gt;"
        let output = HTMLCleaner.cleanHTML(input)

        // Should decode to "&lt;script&gt;" (safe), NOT "<script>" (XSS)
        XCTAssertEqual(output, "&lt;script&gt;", "Double-encoded HTML entities should not result in active tags")
        XCTAssertFalse(output.contains("<script>"), "Should not contain executable script tag")
    }

    /// Test nested entity encoding doesn't produce XSS
    func testHTMLEntityDecodingOrder_NestedEncoding() {
        let input = "&amp;amp;lt;img src=x onerror=alert(1)&amp;amp;gt;"
        let output = HTMLCleaner.cleanHTML(input)

        // Should preserve encoded entities
        XCTAssertFalse(output.contains("<img"), "Should not contain img tag")
        XCTAssertTrue(output.contains("&"), "Should preserve some encoding")
    }

    /// Test that legitimate ampersands are preserved
    func testHTMLEntityDecoding_LegitimateAmpersands() {
        let input = "Tom &amp; Jerry"
        let output = HTMLCleaner.cleanHTML(input)

        XCTAssertEqual(output, "Tom & Jerry", "Should properly decode &amp; to &")
    }

    // MARK: - Basic HTML Cleaning Tests

    func testCleanHTML_RemovesBasicTags() {
        let input = "<p>Hello <strong>world</strong></p>"
        let output = HTMLCleaner.cleanHTML(input)

        XCTAssertEqual(output, "Hello world", "Should remove all HTML tags")
    }

    func testCleanHTML_DecodesHTMLEntities() {
        let input = "&quot;Hello&quot; &lt;World&gt;"
        let output = HTMLCleaner.cleanHTML(input)

        XCTAssertEqual(output, "\"Hello\" <World>", "Should decode all HTML entities")
    }

    func testCleanHTML_CollapsesWhitespace() {
        let input = "Hello    \n\n   World"
        let output = HTMLCleaner.cleanHTML(input)

        XCTAssertEqual(output, "Hello World", "Should collapse multiple whitespace characters")
    }

    func testCleanHTML_HandlesNonBreakingSpace() {
        let input = "Hello&nbsp;World"
        let output = HTMLCleaner.cleanHTML(input)

        XCTAssertEqual(output, "Hello World", "Should convert &nbsp; to regular space")
    }

    func testCleanHTML_EmptyString() {
        let input = ""
        let output = HTMLCleaner.cleanHTML(input)

        XCTAssertEqual(output, "", "Should handle empty string")
    }

    func testCleanHTML_NoHTMLContent() {
        let input = "Just plain text"
        let output = HTMLCleaner.cleanHTML(input)

        XCTAssertEqual(output, "Just plain text", "Should handle plain text without modification")
    }

    // MARK: - Link Extraction Tests

    func testExtractTextFromLinks_BasicLink() {
        let input = "<a href=\"https://example.com\">Click here</a>"
        let output = HTMLCleaner.extractTextFromLinks(input)

        XCTAssertEqual(output, "Click here", "Should extract text from link")
    }

    func testExtractTextFromLinks_MultipleLinks() {
        let input = "<a href=\"url1\">Link 1</a> and <a href=\"url2\">Link 2</a>"
        let output = HTMLCleaner.extractTextFromLinks(input)

        XCTAssertEqual(output, "Link 1 and Link 2", "Should extract text from multiple links")
    }

    func testExtractTextFromLinks_WithOtherTags() {
        let input = "<p>Visit <a href=\"url\">our site</a> for more</p>"
        let output = HTMLCleaner.extractTextFromLinks(input)

        XCTAssertEqual(output, "Visit our site for more", "Should extract link text and remove other tags")
    }

    // MARK: - Mentions Processing Tests

    func testProcessMentions_BasicMention() {
        let input = "<megaplan:mention user_id=\"123\">@JohnDoe</megaplan:mention>"
        let output = HTMLCleaner.processMentions(input)

        XCTAssertEqual(output, "@JohnDoe", "Should extract text from mention tag")
    }

    func testProcessMentions_MultipleMentions() {
        let input = "<megaplan:mention user_id=\"1\">@John</megaplan:mention> and <megaplan:mention user_id=\"2\">@Jane</megaplan:mention>"
        let output = HTMLCleaner.processMentions(input)

        XCTAssertEqual(output, "@John and @Jane", "Should process multiple mentions")
    }

    // MARK: - Full Clean Tests

    func testFullClean_ComplexHTML() {
        let input = "<p>Hello <megaplan:mention user_id=\"1\">@User</megaplan:mention>, check <a href=\"url\">this link</a>!</p>"
        let output = HTMLCleaner.fullClean(input)

        XCTAssertEqual(output, "Hello @User, check this link!", "Should fully clean complex HTML")
    }

    func testFullClean_WithEntities() {
        let input = "<p>&quot;Hello&quot; <a href=\"url\">World</a> &amp; <megaplan:mention>@User</megaplan:mention></p>"
        let output = HTMLCleaner.fullClean(input)

        XCTAssertEqual(output, "\"Hello\" World & @User", "Should clean HTML and decode entities")
    }

    func testFullClean_XSSProtection() {
        let input = "&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;"
        let output = HTMLCleaner.fullClean(input)

        XCTAssertFalse(output.contains("<script>"), "Should protect against XSS via entity encoding")
    }

    // MARK: - Edge Cases

    func testCleanHTML_MalformedTags() {
        let input = "<p>Unclosed paragraph"
        let output = HTMLCleaner.cleanHTML(input)

        XCTAssertEqual(output, "Unclosed paragraph", "Should handle malformed tags")
    }

    func testCleanHTML_NestedTags() {
        let input = "<div><p><span>Nested</span></p></div>"
        let output = HTMLCleaner.cleanHTML(input)

        XCTAssertEqual(output, "Nested", "Should handle nested tags")
    }

    func testCleanHTML_TagsWithAttributes() {
        let input = "<p class=\"text\" id=\"main\">Content</p>"
        let output = HTMLCleaner.cleanHTML(input)

        XCTAssertEqual(output, "Content", "Should remove tags with attributes")
    }

    func testCleanHTML_SelfClosingTags() {
        let input = "Before<br/>After"
        let output = HTMLCleaner.cleanHTML(input)

        XCTAssertEqual(output, "Before After", "Should handle self-closing tags")
    }
}
