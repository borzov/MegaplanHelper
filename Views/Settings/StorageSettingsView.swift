import SwiftUI

struct StorageSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            CacheStatsRow()
                .environmentObject(appState)
        }
        .formStyle(.grouped)
    }
}
