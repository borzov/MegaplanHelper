import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("appTheme") private var theme: String = "system"
    @AppStorage("fontSize") private var fontSize: String = "medium"

    var body: some View {
        Form {
            Section(String(localized: "settings.appearance.themeSection")) {
                Picker(String(localized: "settings.appearance.theme"), selection: $theme) {
                    Text(String(localized: "settings.appearance.theme.system")).tag("system")
                    Text(String(localized: "settings.appearance.theme.light")).tag("light")
                    Text(String(localized: "settings.appearance.theme.dark")).tag("dark")
                }
                .pickerStyle(.segmented)
            }
            Section(String(localized: "settings.appearance.fontSection")) {
                Picker(String(localized: "settings.appearance.fontSize"), selection: $fontSize) {
                    Text(String(localized: "settings.appearance.font.small")).tag("small")
                    Text(String(localized: "settings.appearance.font.medium")).tag("medium")
                    Text(String(localized: "settings.appearance.font.large")).tag("large")
                }
                .pickerStyle(.segmented)
            }
            Section {
                LivePreviewCard()
                    .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}
