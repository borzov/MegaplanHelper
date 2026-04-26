import SwiftUI

struct AuthCredentialsStepView: View {
    let domain: String
    let info: WorkspaceInfo?
    @Binding var login: String
    @Binding var password: String
    @Binding var isPasswordVisible: Bool
    @FocusState.Binding var focus: AuthFieldFocus?
    let isLoading: Bool
    let lockoutState: LockoutState?
    let lastError: AuthFieldError?
    let onBack: () -> Void
    let onSubmit: () -> Void

    @State private var emailValidationTask: Task<Void, Never>?
    @State private var emailError: AuthFieldError?

    private var trimmedLogin: String {
        login.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isLoginValid: Bool {
        trimmedLogin.isValidEmail()
    }

    private var canSubmit: Bool {
        guard !isLoading else { return false }
        if let lockoutState, lockoutState.isActive { return false }
        return isLoginValid && !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceHeaderRow(domain: domain, info: info, onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    loginField
                    passwordField

                    if let banner = currentErrorMessage {
                        InlineErrorBanner(message: banner)
                    }

                    Button(action: onSubmit) {
                        HStack {
                            if isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "key.fill")
                            }
                            Text(isLoading
                                 ? String(localized: "auth.authenticating")
                                 : String(localized: "auth.button"))
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)

                    if let lockoutState, lockoutState.isActive {
                        LockoutCountdownView(lockedUntil: lockoutState.lockedUntil)
                    }
                }
                .padding(20)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var loginField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "auth.login"))
                .font(.subheadline.weight(.medium))

            TextField(String(localized: "auth.login.placeholder"), text: $login)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .focused($focus, equals: .login)
                .onChange(of: login) { _, _ in scheduleEmailValidation() }
                .submitLabel(.next)
                .onSubmit { focus = .password }

            if case .credentials(.invalidEmail) = emailError {
                Text(String(localized: "auth.error.invalidEmail"))
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "auth.password"))
                .font(.subheadline.weight(.medium))

            ZStack(alignment: .trailing) {
                Group {
                    if isPasswordVisible {
                        TextField(String(localized: "auth.password.placeholder"), text: $password)
                    } else {
                        SecureField(String(localized: "auth.password.placeholder"), text: $password)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { if canSubmit { onSubmit() } }

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .symbolEffect(.bounce, value: isPasswordVisible)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .accessibilityLabel(Text(isPasswordVisible
                                         ? String(localized: "auth.passwordToggle.hide")
                                         : String(localized: "auth.passwordToggle.show")))
            }
        }
    }

    private var currentErrorMessage: String? {
        guard let lastError else { return nil }
        switch lastError {
        case .lockout: return nil // shown by LockoutCountdownView
        case .credentials(.invalidEmail) where login.isEmpty: return nil
        default: return lastError.localizedDescription
        }
    }

    private func scheduleEmailValidation() {
        emailValidationTask?.cancel()
        emailValidationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            if Task.isCancelled { return }
            emailError = (!trimmedLogin.isEmpty && !isLoginValid)
                ? .credentials(.invalidEmail)
                : nil
        }
    }
}

#if DEBUG
#Preview("Default") {
    @Previewable @State var login = ""
    @Previewable @State var password = ""
    @Previewable @State var isVisible = false
    @Previewable @FocusState var focus: AuthFieldFocus?
    AuthCredentialsStepView(
        domain: "acme.megaplan.ru",
        info: nil,
        login: $login,
        password: $password,
        isPasswordVisible: $isVisible,
        focus: $focus,
        isLoading: false,
        lockoutState: nil,
        lastError: nil,
        onBack: {},
        onSubmit: {}
    )
    .frame(width: 420, height: 460)
}
#endif
