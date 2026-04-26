import SwiftUI

struct ShortcutsSettingsView: View {
    @StateObject private var manager = HotkeyManager.shared

    var body: some View {
        Form {
            Section(String(localized: "settings.shortcuts.section")) {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    ShortcutRecorderRow(manager: manager, action: action)
                }
            }
            Section {
                Text(String(localized: "settings.shortcuts.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
