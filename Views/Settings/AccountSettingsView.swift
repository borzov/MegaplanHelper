import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var domain: String = ""
    @State private var login: String = ""
    @State private var password: String = ""
    @State private var showingLogoutAlert = false

    var body: some View {
        Form {
            Section {
                AccountCard(
                    displayName: appState.firstName.isEmpty ? appState.username : appState.firstName,
                    email: appState.username,
                    domain: appState.domain,
                    avatar: appState.currentUserAvatar,
                    isConnected: appState.isAuthenticated,
                    lastSyncRelative: appState.formattedLastSync
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section(String(localized: "settings.account.server")) {
                LabeledContent(String(localized: "settings.account.domainLabel")) {
                    TextField("", text: $domain).textFieldStyle(.roundedBorder)
                }
                LabeledContent(String(localized: "settings.account.loginLabel")) {
                    TextField("", text: $login).textFieldStyle(.roundedBorder)
                }
                LabeledContent(String(localized: "settings.account.passwordLabel")) {
                    SecureField("", text: $password).textFieldStyle(.roundedBorder)
                }
            }

            Section {
                HStack {
                    Button(String(localized: "settings.account.reauthenticate")) {
                        Task { await appState.signIn(domain: domain, login: login, password: password) }
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(domain.isEmpty || login.isEmpty || password.isEmpty || appState.isLoading)

                    Button(role: .destructive) {
                        showingLogoutAlert = true
                    } label: {
                        Text(String(localized: "settings.account.signOut"))
                    }
                    .controlSize(.large)
                    .disabled(!appState.isAuthenticated)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            domain = appState.domain
            login = appState.username
        }
        .alert(String(localized: "settings.account.signOutConfirm"), isPresented: $showingLogoutAlert) {
            Button(String(localized: "settings.account.signOut"), role: .destructive) {
                appState.logout()
            }
            Button(String(localized: "general.cancel"), role: .cancel) {}
        }
    }
}
