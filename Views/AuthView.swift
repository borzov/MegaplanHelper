import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case domain
        case login
        case password
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon and description
            VStack(spacing: 16) {
                // App Icon
                Group {
                    if let image = NSImage(named: "MenuBarIcon") {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .colorMultiply(.primary)
                    } else {
                        Image(systemName: "bell.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                
                // Description
                Text(String(localized: "auth.description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            
            Divider()
            
            // Form with credentials
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(String(localized: "auth.domain"), text: Binding(
                            get: { appState.tempCredentials.domain },
                            set: { newValue in
                                var creds = appState.tempCredentials
                                creds.domain = newValue
                                appState.updateTempCredentials(creds)
                            }
                        ))
                        .focused($focusedField, equals: .domain)
                        Text(String(localized: "settings.domainDescription"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(String(localized: "auth.login.placeholder"), text: Binding(
                            get: { appState.tempCredentials.login },
                            set: { newValue in
                                var creds = appState.tempCredentials
                                creds.login = newValue
                                appState.updateTempCredentials(creds)
                            }
                        ))
                        .focused($focusedField, equals: .login)
                        Text(String(localized: "settings.loginDescription"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField(String(localized: "auth.password"), text: Binding(
                            get: { appState.tempCredentials.password },
                            set: { newValue in
                                var creds = appState.tempCredentials
                                creds.password = newValue
                                appState.updateTempCredentials(creds)
                            }
                        ))
                        .focused($focusedField, equals: .password)
                        Text(String(localized: "settings.passwordDescription"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        authenticate()
                    } label: {
                        HStack {
                            if appState.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "key.fill")
                            }
                            Text(appState.isLoading ? String(localized: "auth.authenticating") : String(localized: "auth.button"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(appState.isLoading)
                    .controlSize(.large)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Spacer()
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Quit Application"))
        }
        .onAppear {
            // Only initialize tempCredentials if it's truly empty (first time opening)
            // This prevents overwriting user's entered data
            if appState.tempCredentials.domain.isEmpty && 
               appState.tempCredentials.login.isEmpty && 
               appState.tempCredentials.password.isEmpty {
                appState.updateTempCredentials(MegaplanCredentials(
                    domain: appState.domain,
                    login: appState.username,
                    password: ""
                ))
            }
        }
        .onSubmit {
            switch focusedField {
            case .domain:
                focusedField = .login
            case .login:
                focusedField = .password
            default:
                authenticate()
            }
        }
    }

    private func authenticate() {
        Task {
            await appState.signIn(
                domain: appState.tempCredentials.domain,
                login: appState.tempCredentials.login,
                password: appState.tempCredentials.password
            )
        }
    }
}

#if DEBUG
struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView()
            .environmentObject(AppState())
            .frame(width: 360)
    }
}
#endif
