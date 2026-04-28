import SwiftUI
import XCTest
@testable import MegaplanHepler

final class AppearancePreferencesTests: XCTestCase {

    func testColorScheme_SystemAndUnknown_ReturnNil() {
        XCTAssertNil(AppearanceTheme.colorScheme(for: "system"))
        XCTAssertNil(AppearanceTheme.colorScheme(for: "unexpected"))
    }

    func testColorScheme_LightAndDark_ReturnExplicitScheme() {
        XCTAssertEqual(AppearanceTheme.colorScheme(for: "light"), .light)
        XCTAssertEqual(AppearanceTheme.colorScheme(for: "dark"), .dark)
    }

    func testPopoverFontMetricsResolve_ReturnsExpectedSmallValues() {
        let metrics = PopoverFontMetrics.resolve("small")

        XCTAssertEqual(metrics.iconSmall, 11)
        XCTAssertEqual(metrics.iconMedium, 12)
        XCTAssertEqual(metrics.iconLarge, 34)
        XCTAssertEqual(metrics.sectionHeader, 11)
        XCTAssertEqual(metrics.title, 14)
        XCTAssertEqual(metrics.body, 12)
        XCTAssertEqual(metrics.subBody, 10)
        XCTAssertEqual(metrics.badge, 11)
    }

    func testPopoverFontMetricsResolve_ReturnsExpectedMediumValues() {
        let metrics = PopoverFontMetrics.resolve("medium")

        XCTAssertEqual(metrics.iconSmall, 12)
        XCTAssertEqual(metrics.iconMedium, 14)
        XCTAssertEqual(metrics.iconLarge, 36)
        XCTAssertEqual(metrics.sectionHeader, 12)
        XCTAssertEqual(metrics.title, 15)
        XCTAssertEqual(metrics.body, 13)
        XCTAssertEqual(metrics.subBody, 11)
        XCTAssertEqual(metrics.badge, 12)
    }

    func testPopoverFontMetricsResolve_ReturnsExpectedLargeValues() {
        let metrics = PopoverFontMetrics.resolve("large")

        XCTAssertEqual(metrics.iconSmall, 13)
        XCTAssertEqual(metrics.iconMedium, 16)
        XCTAssertEqual(metrics.iconLarge, 40)
        XCTAssertEqual(metrics.sectionHeader, 13)
        XCTAssertEqual(metrics.title, 17)
        XCTAssertEqual(metrics.body, 14)
        XCTAssertEqual(metrics.subBody, 12)
        XCTAssertEqual(metrics.badge, 13)
    }
}
