import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var domain: String = ""
    @State private var login: String = ""
    @State private var password: String = ""
    @State private var showingLogoutAlert = false
    @State private var isPasswordVisible = false

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
                TextField(String(localized: "settings.account.domainLabel"),
                          text: $domain,
                          prompt: Text("demo.megaplan.ru"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.leading)

                TextField(String(localized: "settings.account.loginLabel"),
                          text: $login,
                          prompt: Text("user@example.com"))
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.leading)

                LabeledContent(String(localized: "settings.account.passwordLabel")) {
                    HStack(spacing: 4) {
                        Group {
                            if isPasswordVisible {
                                TextField("", text: $password, prompt: Text("••••••••"))
                            } else {
                                SecureField("", text: $password, prompt: Text("••••••••"))
                            }
                        }
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.leading)

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                                .symbolEffect(.bounce, value: isPasswordVisible)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: isPasswordVisible
                                     ? "settings.account.hidePassword"
                                     : "settings.account.showPassword"))
                    }
                }
            }

            Section {
                HStack {
                    Button {
                        Task {
                            await appState.signIn(domain: domain, login: login, password: password)
                            if appState.isAuthenticated { password = "" }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if appState.isLoading {
                                ProgressView().controlSize(.small)
                            }
                            Text(String(localized: "settings.account.reauthenticate"))
                        }
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(domain.isEmpty || login.isEmpty || password.isEmpty || appState.isLoading)

                    Spacer()

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
        .onChange(of: appState.domain) { _, new in domain = new }
        .onChange(of: appState.username) { _, new in login = new }
        .alert(String(localized: "settings.account.signOutConfirm"), isPresented: $showingLogoutAlert) {
            Button(String(localized: "settings.account.signOut"), role: .destructive) {
                appState.logout()
            }
            Button(String(localized: "general.cancel"), role: .cancel) {}
        }
    }
}
