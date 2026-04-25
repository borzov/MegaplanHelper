import XCTest
import AppKit
@testable import MegaplanHepler

final class HotkeyManagerTests: XCTestCase {

    func testHotkeyShortcut_EncodeRoundtrip() {
        let original = HotkeyShortcut(keyCode: 15, modifiers: [.command, .shift])
        let encoded = original.encoded
        let decoded = HotkeyShortcut.decode(encoded)
        XCTAssertEqual(decoded, original)
    }

    func testHotkeyShortcut_DisplayString_ContainsModifierSymbols() {
        let s = HotkeyShortcut(keyCode: 0, modifiers: [.command, .option])
        XCTAssertTrue(s.displayString.contains("⌘"))
        XCTAssertTrue(s.displayString.contains("⌥"))
    }

    func testHotkeyShortcut_DecodeInvalid_ReturnsNil() {
        XCTAssertNil(HotkeyShortcut.decode("garbage"))
    }
}
