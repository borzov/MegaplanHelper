import XCTest
@testable import MegaplanHepler

final class SettingsExporterTests: XCTestCase {

    func testExport_KnownKeys_ReturnsJSONString() throws {
        let defaults = UserDefaults(suiteName: "test-export")!
        defaults.set(60, forKey: "refreshInterval")
        defaults.set(true, forKey: "showOnlyUnread")
        defaults.set("system", forKey: "appTheme")

        let exporter = SettingsExporter(defaults: defaults)
        let json = try exporter.export()

        XCTAssertTrue(json.contains("\"refreshInterval\""))
        XCTAssertTrue(json.contains("60"))
        XCTAssertTrue(json.contains("\"showOnlyUnread\""))

        defaults.removeSuite(named: "test-export")
    }

    func testImport_ValidJSON_RestoresDefaults() throws {
        let defaults = UserDefaults(suiteName: "test-import")!
        let exporter = SettingsExporter(defaults: defaults)
        let json = """
        {"refreshInterval":120,"showOnlyUnread":true,"appTheme":"dark"}
        """

        try exporter.importing(json: json)

        XCTAssertEqual(defaults.integer(forKey: "refreshInterval"), 120)
        XCTAssertTrue(defaults.bool(forKey: "showOnlyUnread"))
        XCTAssertEqual(defaults.string(forKey: "appTheme"), "dark")

        defaults.removeSuite(named: "test-import")
    }

    func testImport_InvalidJSON_Throws() {
        let exporter = SettingsExporter(defaults: .standard)
        XCTAssertThrowsError(try exporter.importing(json: "{not json"))
    }
}
