import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @State private var credentials = MegaplanCredentials.empty
    @State private var refreshIntervalValue: Double = Constants.defaultRefreshInterval
    @State private var autoLaunch: Bool = false
    @State private var showingLogoutAlert = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "settings.title"))
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(String(localized: "auth.domain.placeholder"), text: $credentials.domain)
                    Text(String(localized: "settings.domainDescription"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(String(localized: "auth.login"), text: $credentials.login)
                        Text(String(localized: "settings.loginDescription"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField(String(localized: "auth.password"), text: $credentials.password)
                        Text(String(localized: "settings.passwordDescription"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    Button {
                        authenticate()
                    } label: {
                        HStack {
                            if appState.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(appState.isLoading ? String(localized: "auth.authenticating") : String(localized: "auth.button"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(appState.isLoading || appState.isAuthenticated)
                    
                    Button(role: .destructive) {
                        showingLogoutAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text(String(localized: "settings.logout"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!appState.isAuthenticated)
                }
                
                HStack {
                    if appState.isAuthenticated {
                        Label(String(localized: "settings.authenticated"), systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label(String(localized: "settings.notAuthenticated"), systemImage: "xmark.circle.fill")
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }
                .font(.caption)
            } header: {
                Text(String(localized: "settings.account"))
            }
            
            Section {
                Picker(String(localized: "settings.refreshInterval"), selection: $refreshIntervalValue) {
                    Text(String(localized: "settings.interval30"))
                        .tag(30.0)
                    Text(String(localized: "settings.interval60"))
                        .tag(60.0)
                    Text(String(localized: "settings.interval120"))
                        .tag(120.0)
                    Text(String(localized: "settings.interval300"))
                        .tag(300.0)
                    Text(String(localized: "settings.interval600"))
                        .tag(600.0)
                }
                .pickerStyle(.menu)
                .onChange(of: refreshIntervalValue) { newValue in
                    settingsViewModel.updateRefreshInterval(newValue)
                }
                
                Toggle(isOn: Binding(
                    get: { autoLaunch },
                    set: { newValue in
                        autoLaunch = newValue
                        settingsViewModel.updateAutoLaunch(enabled: newValue)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "settings.autoLaunch"))
                        Text(String(localized: "settings.autoLaunchDescription"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "settings.preferences"))
            }
            
            Section {
                Toggle(isOn: Binding(
                    get: { settingsViewModel.notificationsEnabled },
                    set: { settingsViewModel.updateNotificationsEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "settings.notifications.enabled"))
                        Text(String(localized: "settings.notifications.enabledDescription"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle(isOn: Binding(
                    get: { settingsViewModel.groupingEnabled },
                    set: { settingsViewModel.updateGroupingEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "settings.notifications.grouping"))
                        Text(String(localized: "settings.notifications.groupingDescription"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "settings.notifications"))
            }
            
            Section {
                Picker(String(localized: "settings.theme"), selection: Binding(
                    get: { settingsViewModel.theme },
                    set: { settingsViewModel.updateTheme($0) }
                )) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.menu)
                
                Picker(String(localized: "settings.fontSize"), selection: Binding(
                    get: { settingsViewModel.fontSize },
                    set: { settingsViewModel.updateFontSize($0) }
                )) {
                    ForEach(FontSize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text(String(localized: "settings.appearance"))
            }
            
            Section {
                Toggle(isOn: Binding(
                    get: { settingsViewModel.showOnlyUnread },
                    set: { settingsViewModel.updateShowOnlyUnread($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "settings.showOnlyUnread"))
                        Text(String(localized: "settings.showOnlyUnreadDescription"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "settings.behavior"))
            }
            
            Section {
                HStack {
                    Spacer()
                    Text(String(format: String(localized: "settings.version"), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 500)
        .onAppear(perform: syncState)
        .alert(String(localized: "settings.logoutAlertTitle"), isPresented: $showingLogoutAlert) {
            Button(String(localized: "general.cancel"), role: .cancel) { }
            Button(String(localized: "settings.logout"), role: .destructive) {
                Task {
                    await appState.logout()
                }
            }
        } message: {
            Text(String(localized: "settings.logoutAlertMessage"))
        }
    }

    private func syncState() {
        credentials.domain = appState.domain
        credentials.login = appState.username
        refreshIntervalValue = settingsViewModel.refreshInterval
        autoLaunch = settingsViewModel.autoLaunchEnabled
    }

    private func authenticate() {
        Task {
            await appState.signIn(
                domain: credentials.domain,
                login: credentials.login,
                password: credentials.password
            )
            syncState()
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppState())
            .frame(width: 480, height: 500)
    }
}
#endif
