import AppKit
import Combine

/// Identifier for a user-bindable hotkey action.
enum HotkeyAction: String, CaseIterable {
    case openPopover
    case refreshNow
    case focusSearch
    case markAllRead

    var titleKey: LocalizedStringResource {
        switch self {
        case .openPopover: return "shortcuts.action.openPopover"
        case .refreshNow: return "shortcuts.action.refreshNow"
        case .focusSearch: return "shortcuts.action.focusSearch"
        case .markAllRead: return "shortcuts.action.markAllRead"
        }
    }
}

/// Encapsulates a key + modifier flags combination.
struct HotkeyShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    /// Compact "keyCode:modifiers" string, suitable for UserDefaults.
    var encoded: String {
        "\(keyCode):\(modifiers.rawValue)"
    }

    /// Human-readable: "⌘⇧A".
    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += keyName(keyCode)
        return s
    }

    static func decode(_ raw: String) -> HotkeyShortcut? {
        let parts = raw.split(separator: ":")
        guard parts.count == 2,
              let keyCode = UInt16(parts[0]),
              let modsRaw = UInt(parts[1]) else { return nil }
        let modifiers = NSEvent.ModifierFlags(rawValue: modsRaw)
            .intersection(.deviceIndependentFlagsMask)
        return HotkeyShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private func keyName(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            // Letters
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F",
            5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L",
            46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R",
            1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z",
            // Digits (top row)
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
            23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
            // Function keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            // Arrows
            123: "←", 124: "→", 125: "↓", 126: "↑",
            // Common controls
            53: "Esc", 36: "↵", 51: "⌫", 49: "Space", 48: "⇥",
            // Punctuation
            43: ",", 47: ".", 44: "/", 41: ";", 39: "'",
            33: "[", 30: "]", 42: "\\", 50: "`", 27: "-", 24: "="
        ]
        return map[code] ?? "(\(code))"
    }
}

/// Coordinates registration of user-defined hotkeys via local NSEvent monitor.
/// Stores bindings in UserDefaults under "hotkey.<action>" keys.
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published private(set) var bindings: [HotkeyAction: HotkeyShortcut] = [:]
    private var monitor: Any?
    private let defaults = UserDefaults.standard
    private let keyPrefix = "hotkey."

    /// Action handlers registered by the popover/list views.
    private var handlers: [HotkeyAction: () -> Void] = [:]

    private init() {
        loadBindings()
    }

    private func loadBindings() {
        for action in HotkeyAction.allCases {
            if let raw = defaults.string(forKey: keyPrefix + action.rawValue),
               let shortcut = HotkeyShortcut.decode(raw) {
                bindings[action] = shortcut
            }
        }
    }

    /// Binds `action` to `shortcut`. If another action currently holds the same
    /// combination, that action is automatically unbound first ("stealing" — same
    /// pattern as Linear, Things 3, Raycast). The supplied `modifiers` are masked
    /// to `.deviceIndependentFlagsMask` to ensure persistence cannot drift.
    func bind(_ action: HotkeyAction, to shortcut: HotkeyShortcut) {
        let canonical = HotkeyShortcut(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.modifiers.intersection(.deviceIndependentFlagsMask)
        )
        // Steal the shortcut from any other action that currently holds it.
        for (otherAction, otherShortcut) in bindings where otherAction != action && otherShortcut == canonical {
            unbind(otherAction)
        }
        bindings[action] = canonical
        defaults.set(canonical.encoded, forKey: keyPrefix + action.rawValue)
    }

    func unbind(_ action: HotkeyAction) {
        bindings.removeValue(forKey: action)
        defaults.removeObject(forKey: keyPrefix + action.rawValue)
    }

    func register(_ action: HotkeyAction, handler: @escaping () -> Void) {
        handlers[action] = handler
        ensureMonitor()
    }

    private func ensureMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            for (action, shortcut) in self.bindings {
                let pressedMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.keyCode == shortcut.keyCode &&
                   pressedMods == shortcut.modifiers {
                    self.handlers[action]?()
                    return nil
                }
            }
            return event
        }
    }

    deinit {
        // Defensive cleanup. The shared singleton typically lives until process exit,
        // so this branch primarily exists for testability.
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
