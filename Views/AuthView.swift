import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @State private var credentials = MegaplanCredentials.empty
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case domain
        case login
        case password
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("auth.title")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                Text("auth.domain")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("auth.domain.placeholder", text: $credentials.domain)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .domain)

                Text("auth.login")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
                TextField("auth.login.placeholder", text: $credentials.login)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .login)

                Text("auth.password")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
                SecureField("auth.password.placeholder", text: $credentials.password)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .password)
            }

            Button {
                authenticate()
            } label: {
                HStack {
                    if appState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    }
                    Text(appState.isLoading ? "auth.authenticating" : "auth.button")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLoading)

            Spacer(minLength: 0)
        }
        .onAppear(perform: populateFromState)
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

    private func populateFromState() {
        credentials.domain = appState.domain
        credentials.login = appState.username
    }

    private func authenticate() {
        Task {
            await appState.signIn(
                domain: credentials.domain,
                login: credentials.login,
                password: credentials.password
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
