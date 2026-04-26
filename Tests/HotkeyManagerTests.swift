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

    func testHotkeyShortcut_ModifierGlyphOrder_IsControlOptionShiftCommand() {
        let s = HotkeyShortcut(keyCode: 0, modifiers: [.control, .command])
        // Order is fixed: ⌃ first, ⌘ last; nothing in between for this combination.
        XCTAssertEqual(s.displayString, "⌃⌘A")
    }

    func testHotkeyShortcut_DecodeMalformedInputs_ReturnNil() {
        XCTAssertNil(HotkeyShortcut.decode(""))
        XCTAssertNil(HotkeyShortcut.decode("15"))
        XCTAssertNil(HotkeyShortcut.decode("15:"))
        XCTAssertNil(HotkeyShortcut.decode(":1310720"))
        XCTAssertNil(HotkeyShortcut.decode("15:abc"))
        XCTAssertNil(HotkeyShortcut.decode("15:1310720:extra"))
    }

    func testHotkeyShortcut_DecodeStripsExtraneousModifiers() {
        // Construct an encoded value whose modifier rawValue includes bits outside
        // .deviceIndependentFlagsMask (e.g. .numericPad = 1 << 21 = 2097152).
        // After decode, only the device-independent bits should remain.
        let extraneous = NSEvent.ModifierFlags.numericPad.rawValue
        let encoded = "15:\(extraneous)"
        let decoded = HotkeyShortcut.decode(encoded)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.modifiers, [], "numericPad bit must be stripped on decode")
    }
}
