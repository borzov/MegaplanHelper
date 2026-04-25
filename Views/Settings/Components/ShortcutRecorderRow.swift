import SwiftUI
import AppKit

/// One row that displays an action title and lets the user re-bind its global hotkey.
/// Click "Record" → press a combination → stored via HotkeyManager.
struct ShortcutRecorderRow: View {
    @ObservedObject var manager: HotkeyManager
    let action: HotkeyAction

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(action.titleKey)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if isRecording {
                    Text(String(localized: "shortcuts.recording"))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                } else if let s = manager.bindings[action] {
                    Text(s.displayString)
                        .font(.body.monospaced())
                        .padding(.horizontal, 8)
                } else {
                    Text(String(localized: "shortcuts.notSet"))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
            }
            .frame(minWidth: 90, minHeight: 22)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))

            Button(action: toggleRecording) {
                Text(isRecording
                     ? String(localized: "shortcuts.stop")
                     : String(localized: "shortcuts.record"))
            }
            .controlSize(.small)

            if manager.bindings[action] != nil && !isRecording {
                Button(role: .destructive) {
                    manager.unbind(action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "shortcuts.clear"))
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels recording without binding.
            if event.keyCode == Self.escapeKeyCode {
                stopRecording()
                return nil
            }
            let pressedMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !pressedMods.isEmpty else { return event }
            let shortcut = HotkeyShortcut(keyCode: event.keyCode, modifiers: pressedMods)
            manager.bind(action, to: shortcut)
            stopRecording()
            return nil
        }
    }

    private static let escapeKeyCode: UInt16 = 53

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
