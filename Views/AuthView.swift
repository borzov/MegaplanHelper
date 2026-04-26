import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var probeService = DomainProbeServiceHolder()

    @State private var step: AuthFormStep = .domain
    @State private var domain: String = ""
    @State private var login: String = ""
    @State private var password: String = ""
    @State private var probeState: DomainProbeState = .idle
    @State private var isPasswordVisible: Bool = false
    @FocusState private var focus: AuthFieldFocus?

    @State private var probeTask: Task<Void, Never>?

    private let domainStepWidth: CGFloat = 370
    private let credentialsStepWidth: CGFloat = 420
    private let popoverHeight: CGFloat = 500

    var body: some View {
        ZStack {
            switch step {
            case .domain:
                AuthDomainStepView(
                    domain: $domain,
                    probeState: $probeState,
                    focus: $focus,
                    onContinue: handleContinue
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .onAppear { focus = .domain }
                .onChange(of: domain) { _, newValue in scheduleProbe(newValue) }

            case .credentials(let confirmedDomain, let info):
                AuthCredentialsStepView(
                    domain: confirmedDomain,
                    info: info,
                    login: $login,
                    password: $password,
                    isPasswordVisible: $isPasswordVisible,
                    focus: $focus,
                    isLoading: appState.isLoading,
                    lockoutState: appState.lockoutState,
                    lastError: appState.lastAuthError,
                    onBack: handleBack,
                    onSubmit: handleSubmit
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .onAppear {
                    focus = .login
                    Task { await restoreSavedPassword(domain: confirmedDomain) }
                }
            }
        }
        .frame(width: currentWidth, height: popoverHeight)
        .animation(.easeInOut(duration: 0.28), value: step)
        .onAppear { hydrateInitialState() }
        .onChange(of: step) { _, _ in updatePopoverSize() }
    }

    // MARK: - Layout

    private var currentWidth: CGFloat {
        switch step {
        case .domain: return domainStepWidth
        case .credentials: return credentialsStepWidth
        }
    }

    private func updatePopoverSize() {
        StatusBarController.current?.setPopoverContentSize(
            width: currentWidth, height: popoverHeight, animated: true
        )
    }

    // MARK: - Handlers

    private func hydrateInitialState() {
        if domain.isEmpty { domain = appState.domain }
        if login.isEmpty { login = appState.username }
        appState.lastAuthError = nil
    }

    private func scheduleProbe(_ raw: String) {
        probeTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            probeState = .idle
            return
        }
        probeState = .probing
        probeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let result = await probeService.service.probe(trimmed)
            if Task.isCancelled { return }
            probeState = result
        }
    }

    private func handleContinue() {
        var info: WorkspaceInfo?
        if case .online(let workspace) = probeState { info = workspace }

        let confirmed = info?.canonicalDomain ?? domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !confirmed.isEmpty else { return }

        appState.lastAuthError = nil
        withAnimation(.easeInOut(duration: 0.28)) {
            step = .credentials(domain: confirmed, info: info)
        }
    }

    private func handleBack() {
        withAnimation(.easeInOut(duration: 0.28)) {
            step = .domain
        }
        appState.lastAuthError = nil
    }

    private func handleSubmit() {
        Task {
            guard case .credentials(let confirmedDomain, _) = step else { return }
            await appState.signIn(domain: confirmedDomain, login: login, password: password)
        }
    }

    private func restoreSavedPassword(domain: String) async {
        guard password.isEmpty else { return }
        if let saved = await appState.loadSavedCredentialsFromKeychain(domain: domain, login: login),
           !saved.isEmpty {
            password = saved
        }
    }
}

/// Wraps DomainProbeService in an ObservableObject so SwiftUI keeps it alive
/// across view updates. The actor itself is internally synchronized.
@MainActor
final class DomainProbeServiceHolder: ObservableObject {
    let service = DomainProbeService()
}

#if DEBUG
struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView()
            .environmentObject(AppState())
    }
}
#endif
