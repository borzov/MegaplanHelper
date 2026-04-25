import XCTest
@testable import MegaplanHepler

final class SettingsExporterTests: XCTestCase {

    func testExport_KnownKeys_ReturnsJSONString() throws {
        let suite = "test-export"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removeSuite(named: suite) }

        defaults.set(60, forKey: "refreshInterval")
        defaults.set(true, forKey: "showOnlyUnread")
        defaults.set("system", forKey: "appTheme")

        let exporter = SettingsExporter(defaults: defaults)
        let json = try exporter.export()

        XCTAssertTrue(json.contains("\"refreshInterval\""))
        XCTAssertTrue(json.contains("60"))
        XCTAssertTrue(json.contains("\"showOnlyUnread\""))
    }

    func testImport_ValidJSON_RestoresDefaults() throws {
        let suite = "test-import"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removeSuite(named: suite) }

        let exporter = SettingsExporter(defaults: defaults)
        let json = """
        {"refreshInterval":120,"showOnlyUnread":true,"appTheme":"dark"}
        """

        try exporter.importing(json: json)

        XCTAssertEqual(defaults.integer(forKey: "refreshInterval"), 120)
        XCTAssertTrue(defaults.bool(forKey: "showOnlyUnread"))
        XCTAssertEqual(defaults.string(forKey: "appTheme"), "dark")
    }

    func testImport_InvalidJSON_Throws() {
        let suite = "test-invalid-json"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removeSuite(named: suite) }

        let exporter = SettingsExporter(defaults: defaults)
        XCTAssertThrowsError(try exporter.importing(json: "{not json"))
    }

    func testImport_WrongType_ThrowsAndDoesNotMutate() throws {
        let suite = "test-import-wrongtype"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removeSuite(named: suite) }

        defaults.set(60, forKey: "refreshInterval")  // pre-existing valid value

        let exporter = SettingsExporter(defaults: defaults)
        let bad = #"{"refreshInterval":"not-a-number","appTheme":"dark"}"#

        XCTAssertThrowsError(try exporter.importing(json: bad)) { error in
            guard case SettingsExporter.ExportError.invalidValueType(let key, _) = error else {
                return XCTFail("Expected invalidValueType, got \(error)")
            }
            XCTAssertEqual(key, "refreshInterval")
        }

        // Pre-existing value preserved, partner key not mutated.
        XCTAssertEqual(defaults.integer(forKey: "refreshInterval"), 60)
        XCTAssertNil(defaults.string(forKey: "appTheme"))
    }

    func testImport_UnknownKey_StillSilentlyIgnored() throws {
        let suite = "test-import-unknown"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removeSuite(named: suite) }

        let exporter = SettingsExporter(defaults: defaults)
        let json = #"{"appTheme":"dark","authToken":"secret-leak"}"#

        XCTAssertNoThrow(try exporter.importing(json: json))
        XCTAssertEqual(defaults.string(forKey: "appTheme"), "dark")
        XCTAssertNil(defaults.string(forKey: "authToken"), "Non-whitelisted key must not be persisted")
    }
}
