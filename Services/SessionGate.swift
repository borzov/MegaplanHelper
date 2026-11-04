import Foundation

/// Sign-in, lockout, and the session token.
///
/// `isAuthenticated` is stored only here. Feed refresh keeps `AppState.isLoading`.
@MainActor
final class SessionGate {
    private weak var host: AppState?
    private let keychain: KeychainStoring

    // Фасад AppState не хранит копию: сигнал для SwiftUI уходит отсюда.
    private(set) var isSigningIn = false {
        willSet { host?.objectWillChange.send() }
    }
    private(set) var isAuthenticated = false
    private(set) var lockoutState: LockoutState? {
        willSet { host?.objectWillChange.send() }
    }
    var lastAuthError: AuthFieldError? {
        willSet { host?.objectWillChange.send() }
    }
    /// Session token. Callers install or drop the API client from this value.
    var token: String?

    private var cachedPasswordData: Data?
    private static let lockoutDuration: TimeInterval = 15 * 60
    private var failedLoginAttempts = 0
    private var lastFailedLoginTime: Date?
    private var isSessionRestored = false

    init(keychain: KeychainStoring) {
        self.keychain = keychain
    }

    func attach(_ host: AppState) {
        self.host = host
    }

    func setStoredAuthenticated(_ value: Bool) {
        isAuthenticated = value
    }

    func signIn(domain: String, login: String, password: String) async {
        guard let host else { return }

        // Brute force protection: 15 minutes lockout after 3 failed attempts
        if failedLoginAttempts >= 3,
           let lastTime = lastFailedLoginTime {
            if Date().timeIntervalSince(lastTime) < Self.lockoutDuration {
                lastAuthError = .lockout
                recomputeLockoutState()
                return
            } else {
                // Lockout period has expired, reset the counter
                failedLoginAttempts = 0
                lastFailedLoginTime = nil
                recomputeLockoutState()
            }
        }

        isSigningIn = true
        defer { isSigningIn = false }

        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousWorkspaceKey = AppState.workspaceKey(from: host.domain)

        if trimmedDomain.isEmpty {
            lastAuthError = .domain(.invalidFormat)
            return
        }
        if !trimmedLogin.isValidEmail() {
            lastAuthError = .credentials(.invalidEmail)
            return
        }
        if password.isEmpty {
            lastAuthError = .credentials(.emptyPassword)
            return
        }

        // Домен нужен запросу сразу, но неудачный логин установленный клиент не подменяет.
        let authAPI = host.installedDomain == trimmedDomain
            ? host.api
            : host.api.withCredentials(domain: trimmedDomain, token: nil)
        do {
            let token = try await authAPI.authenticate(login: trimmedLogin, password: password)
            try persistCredentials(domain: trimmedDomain, login: trimmedLogin, password: password, token: token)
            host.installAPI(domain: trimmedDomain, token: token)
            if previousWorkspaceKey != AppState.workspaceKey(from: trimmedDomain) {
                await host.snapshotStore.clear()
            }
            lastAuthError = nil
            host.commitAuthenticated(true)

            // Validate token and check admin permissions
            do {
                let result = try await host.api.validateToken()
                host.applyTokenValidationResult(result)
                AppLogger.info("Authentication succeeded for \(trimmedLogin). Admin: \(host.isAdmin)")
            } catch {
                AppLogger.warning("Failed to validate token after authentication: \(error.localizedDescription)")
                // Continue anyway, admin check will happen on next token validation
            }

            // Reset failed attempts on success
            failedLoginAttempts = 0
            lastFailedLoginTime = nil
            recomputeLockoutState()

            // Clear cached password after successful authentication if session was already restored
            // This reduces the time password stays in memory
            if isSessionRestored {
                AppLogger.info("Clearing cached password after successful authentication")
                clearCachedPassword()
            }

            await host.startRefreshTimer()
            await host.refresh()
        } catch {
            // Increment failed attempts
            failedLoginAttempts += 1
            lastFailedLoginTime = Date()
            recomputeLockoutState()

            let networkError = NetworkError(error)
            AppLogger.error("Authentication failed: \(networkError.localizedDescription)")
            lastAuthError = AuthFieldError(networkError: networkError)
        }
    }

    func logout() async {
        guard let host else { return }
        host.isShuttingDown = true

        let currentUsername = host.username
        let currentDomain = host.domain

        token = nil
        host.installAPI(domain: currentDomain, token: nil)
        clearCachedPassword()

        host.sync.reset()
        host.commitAuthenticated(false)
        host.isAdmin = false
        host.firstName = ""
        host.certificatePinningFailed = false
        host.publishSyncedFeed()
        await host.stopRefreshTimer()

        host.isShuttingDown = false

        // Reset certificate pinning state for next session
        MegaplanAPI.resetPinningState()

        // Clear user info cache
        Task {
            await UserInfoCache.shared.clearCache()
            await UserInfoResolver.shared.clearAvatarMisses()
            AppLogger.debug("Cleared user info cache")
        }
        Task {
            await host.snapshotStore.clear()
        }

        do {
            try keychain.delete(service: Constants.Keychain.service, account: Constants.Keychain.tokenAccount)
            if !currentUsername.isEmpty {
                let account = Constants.Keychain.passwordAccount(for: currentUsername, domain: currentDomain)
                try keychain.delete(service: Constants.Keychain.service, account: account)
            }
            AppLogger.info("User logged out")
        } catch {
            AppLogger.error("Failed to clear keychain during logout: \(error.localizedDescription)")
        }

        // Очистка пароля из tempCredentials для безопасности, сохраняя domain/login для удобства
        host.tempCredentials.password = ""

        host.domain = ""
        host.username = ""

        host.userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.domain)
        host.userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.username)
    }

    /// Returns the password saved for (domain, login) if it matches the
    /// currently-stored credentials, otherwise nil. Used by AuthView wizard
    /// to restore the password field when the user returns to Step 2.
    func loadSavedCredentialsFromKeychain(domain: String, login: String) async -> String? {
        guard let host else { return nil }
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDomain.isEmpty, !trimmedLogin.isEmpty else { return nil }

        let rawStoredDomain = host.userDefaults.string(forKey: Constants.UserDefaultsKeys.domain) ?? ""
        let storedDomain = rawStoredDomain.lowercased()
        let storedLogin = host.userDefaults.string(forKey: Constants.UserDefaultsKeys.username) ?? ""

        guard storedDomain == trimmedDomain, storedLogin == trimmedLogin else { return nil }

        let account = Constants.Keychain.passwordAccount(for: storedLogin, domain: rawStoredDomain)
        do {
            return try keychain.read(service: Constants.Keychain.service, account: account)
        } catch {
            AppLogger.warning("Keychain read failed in loadSavedCredentialsFromKeychain: \(error.localizedDescription)")
            return nil
        }
    }

    func restoreSession() async {
        guard let host else { return }
        guard !host.domain.isEmpty else {
            AppLogger.debug("No stored domain, skipping session restore")
            return
        }

        await host.restoreSnapshotIfAvailable(for: host.domain)

        do {
            if let storedToken = try keychain.read(service: Constants.Keychain.service, account: Constants.Keychain.tokenAccount) {
                token = storedToken
            }
            if !host.username.isEmpty {
                let account = Constants.Keychain.passwordAccount(for: host.username, domain: host.domain)
                if let passwordString = try? keychain.read(service: Constants.Keychain.service, account: account) {
                    cachedPasswordData = passwordString.data(using: .utf8)
                }
            }
        } catch {
            AppLogger.error("Failed to read credentials from keychain: \(error.localizedDescription)")
        }

        guard let token else {
            AppLogger.debug("No token available, showing auth view")
            return
        }

        host.installAPI(domain: host.domain, token: token)
        do {
            let result = try await host.api.validateToken()
            if result.isValid {
                host.commitAuthenticated(true)
                isSessionRestored = true
                host.applyTokenValidationResult(result)
                AppLogger.info("Token validation succeeded, restoring session. Admin: \(host.isAdmin)")
                await host.startRefreshTimer()
                await host.refresh()

                // Clear cached password after successful session restore to minimize exposure time
                AppLogger.info("Clearing cached password after successful session restore")
                clearCachedPassword()
            } else if let passwordData = cachedPasswordData,
                      let password = String(data: passwordData, encoding: .utf8) {
                AppLogger.debug("Token invalid, attempting re-authentication")
                await signIn(domain: host.domain, login: host.username, password: password)
            } else {
                AppLogger.debug("Token invalid and no password cached")
                await logout()
            }
        } catch NetworkError.unauthorized {
            AppLogger.debug("Token unauthorized, attempting re-authentication")
            if let passwordData = cachedPasswordData,
               let password = String(data: passwordData, encoding: .utf8) {
                await signIn(domain: host.domain, login: host.username, password: password)
            } else {
                await logout()
            }
        } catch {
            let mappedError = NetworkError(error)
            if host.isTransientNetworkFailure(mappedError) {
                host.isOffline = true
                AppLogger.info("Token validation failed due to transient network issue: \(mappedError.localizedDescription)")
                return
            }
            AppLogger.error("Token validation failed: \(error.localizedDescription)")
            host.presentError(mappedError)
        }
    }

    func persistCredentials(domain: String, login: String, password: String, token: String) throws {
        guard let host else { return }
        self.token = token
        cachedPasswordData = password.data(using: .utf8)

        host.username = login
        host.domain = domain

        host.userDefaults.set(domain, forKey: Constants.UserDefaultsKeys.domain)
        host.userDefaults.set(login, forKey: Constants.UserDefaultsKeys.username)

        try keychain.save(token, service: Constants.Keychain.service, account: Constants.Keychain.tokenAccount)
        let account = Constants.Keychain.passwordAccount(for: login, domain: domain)
        try keychain.save(password, service: Constants.Keychain.service, account: account)
    }

    func clearCachedPassword() {
        // Securely clear password from memory
        guard var data = cachedPasswordData else { return }
        data.resetBytes(in: 0..<data.count)
        cachedPasswordData = nil
    }

    func recomputeLockoutState() {
        if failedLoginAttempts >= 3,
           let lastTime = lastFailedLoginTime,
           Date().timeIntervalSince(lastTime) < Self.lockoutDuration {
            lockoutState = LockoutState(
                lockedUntil: lastTime.addingTimeInterval(Self.lockoutDuration),
                attemptCount: failedLoginAttempts
            )
        } else {
            lockoutState = nil
        }
    }
}
