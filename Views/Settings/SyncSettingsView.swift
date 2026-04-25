import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("autoLaunchEnabled") private var autoLaunch: Bool = false
    @AppStorage("showOnlyUnread") private var showOnlyUnread: Bool = false

    var body: some View {
        Form {
            Section(String(localized: "settings.sync.refreshSection")) {
                RefreshIntervalSlider(seconds: $refreshInterval)
                    .onChange(of: refreshInterval) { _, newValue in
                        appState.updateRefreshInterval(newValue)
                    }
            }
            Section(String(localized: "settings.sync.startupSection")) {
                Toggle(String(localized: "settings.sync.autoLaunch"), isOn: $autoLaunch)
                    .onChange(of: autoLaunch) { _, newValue in
                        appState.updateAutoLaunch(enabled: newValue)
                    }
                Toggle(String(localized: "settings.sync.showOnlyUnread"), isOn: $showOnlyUnread)
            }
        }
        .formStyle(.grouped)
    }
}
