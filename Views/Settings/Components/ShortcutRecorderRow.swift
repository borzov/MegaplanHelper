import SwiftUI
import AppKit

/// One row that displays an action title and lets the user re-bind its global hotkey.
/// Mirrors the macOS System Settings → Keyboard → Shortcuts pattern: a single
/// clickable pill on the trailing edge that toggles a recording session.
///
/// Interactions:
///  - Click on the pill                — start recording.
///  - Press a key combination          — bind it via `HotkeyManager.bind(_:to:)`.
///  - Press `Esc` while recording      — cancel without changing the binding.
///  - Right-click on a bound pill      — context menu with "Clear".
///  - Click on the pill again          — stop recording.
struct ShortcutRecorderRow: View {
    @ObservedObject var manager: HotkeyManager
    let action: HotkeyAction

    @State private var isRecording = false
    @State private var isHovered = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            Text(action.titleKey)
                .frame(maxWidth: .infinity, alignment: .leading)

            pill
        }
        .contentShape(Rectangle())
        .onDisappear { stopRecording() }
    }

    private var pill: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 4) {
                pillContent
            }
            .frame(minWidth: 110, minHeight: 22)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(pillBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(pillBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.12)) { isHovered = hovering }
        }
        .help(helpText)
        .contextMenu {
            if let _ = manager.bindings[action], !isRecording {
                Button(String(localized: "shortcuts.clear"), role: .destructive) {
                    manager.unbind(action)
                }
            }
        }
    }

    @ViewBuilder
    private var pillContent: some View {
        if isRecording {
            Image(systemName: "record.circle.fill")
                .symbolEffect(.pulse.byLayer, options: .repeating)
                .foregroundStyle(.red)
            Text(String(localized: "shortcuts.recording"))
                .foregroundStyle(.secondary)
                .font(.callout)
        } else if let shortcut = manager.bindings[action] {
            Text(shortcut.displayString)
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
        } else {
            Text(String(localized: "shortcuts.clickToRecord"))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var pillBackground: some ShapeStyle {
        if isRecording {
            return AnyShapeStyle(.tint.opacity(0.18))
        }
        if isHovered {
            return AnyShapeStyle(.quaternary.opacity(0.7))
        }
        return AnyShapeStyle(.quaternary.opacity(0.4))
    }

    private var pillBorder: Color {
        if isRecording { return .accentColor }
        if isHovered { return Color.primary.opacity(0.12) }
        return Color.primary.opacity(0.06)
    }

    private var helpText: String {
        if isRecording {
            return String(localized: "shortcuts.helpRecording")
        }
        if manager.bindings[action] != nil {
            return String(localized: "shortcuts.helpBound")
        }
        return String(localized: "shortcuts.helpUnbound")
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

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private static let escapeKeyCode: UInt16 = 53
}
