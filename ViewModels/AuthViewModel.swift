import Combine
import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var domain: String = ""
    @Published var login: String = ""
    @Published var password: String = ""
    @Published var isAuthenticating: Bool = false
    @Published var errorMessage: String?
    @Published var isAuthenticated: Bool = false
    @Published var firstName: String = ""
    
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    
    init(appState: AppState) {
        self.appState = appState
        
        // Синхронизируем состояние авторизации
        appState.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthenticated)
        
        appState.$domain
            .receive(on: DispatchQueue.main)
            .assign(to: &$domain)
        
        appState.$username
            .receive(on: DispatchQueue.main)
            .assign(to: &$login)
        
        appState.$firstName
            .receive(on: DispatchQueue.main)
            .assign(to: &$firstName)
        
        // Подписываемся на ошибки
        appState.$alertItem
            .compactMap { $0?.message }
            .receive(on: DispatchQueue.main)
            .assign(to: &$errorMessage)
    }
    
    func signIn() async {
        guard !domain.isEmpty, !login.isEmpty, !password.isEmpty else {
            errorMessage = String(localized: "error.validation")
            return
        }
        
        isAuthenticating = true
        errorMessage = nil
        
        await appState.signIn(domain: domain, login: login, password: password)
        
        isAuthenticating = false
    }
    
    func logout() {
        appState.logout()
        password = ""
    }
    
    func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

