import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var credentials = MegaplanCredentials.empty
    @State private var refreshIntervalValue: Double = Constants.defaultRefreshInterval
    @State private var autoLaunch: Bool = false
    @State private var showingLogoutAlert = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Настройки")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Ваш домен *.megaplan.ru", text: $credentials.domain)
                    Text("Укажите актуальный адрес вашего сервера Megaplan")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Логин", text: $credentials.login)
                        Text("Email адрес для входа в систему")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("Пароль", text: $credentials.password)
                        Text("Пароль от вашего аккаунта")
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
                            Text(appState.isLoading ? "Авторизация..." : "Войти")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(appState.isLoading || appState.isAuthenticated)
                    
                    Button(role: .destructive) {
                        showingLogoutAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Выйти")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!appState.isAuthenticated)
                }
                
                HStack {
                    if appState.isAuthenticated {
                        Label("Авторизован", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Не авторизован", systemImage: "xmark.circle.fill")
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }
                .font(.caption)
            } header: {
                Text("Аккаунт")
            }
            
            Section {
                Picker("Интервал обновления", selection: $refreshIntervalValue) {
                    Text("30 секунд").tag(30.0)
                    Text("1 минута").tag(60.0)
                    Text("2 минуты").tag(120.0)
                    Text("5 минут").tag(300.0)
                    Text("10 минут").tag(600.0)
                }
                .pickerStyle(.menu)
                .onChange(of: refreshIntervalValue) { newValue in
                    appState.updateRefreshInterval(newValue)
                }
                
                Toggle(isOn: Binding(
                    get: { autoLaunch },
                    set: { newValue in
                        autoLaunch = newValue
                        appState.updateAutoLaunch(enabled: newValue)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Автозапуск")
                        Text("Запускать приложение при входе в систему")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Настройки")
            }
            
            Section {
                HStack {
                    Spacer()
                    Text("Версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
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
        .alert("Выйти из аккаунта?", isPresented: $showingLogoutAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Выйти", role: .destructive) {
                Task {
                    await appState.logout()
                }
            }
        } message: {
            Text("Вы уверены, что хотите выйти из аккаунта?")
        }
    }

    private func syncState() {
        credentials.domain = appState.domain
        credentials.login = appState.username
        refreshIntervalValue = appState.refreshInterval
        autoLaunch = appState.autoLaunchEnabled
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
