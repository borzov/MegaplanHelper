import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var refreshInterval: Double = Constants.defaultRefreshInterval
    @Published var autoLaunchEnabled: Bool = false
    @Published var notificationsEnabled: Bool = true
    @Published var groupingEnabled: Bool = true
    @Published var showOnlyUnread: Bool = false
    @Published var theme: AppTheme = .system
    @Published var fontSize: FontSize = .medium
    
    private let appState: AppState
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    
    init(appState: AppState, userDefaults: UserDefaults = .standard) {
        self.appState = appState
        self.userDefaults = userDefaults
        
        // Загружаем настройки
        loadSettings()
        
        // Синхронизируем с AppState
        appState.$refreshInterval
            .receive(on: DispatchQueue.main)
            .assign(to: &$refreshInterval)
        
        appState.$autoLaunchEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$autoLaunchEnabled)
    }
    
    func updateRefreshInterval(_ interval: Double) {
        refreshInterval = max(15, interval)
        userDefaults.set(refreshInterval, forKey: Constants.UserDefaultsKeys.refreshInterval)
        appState.updateRefreshInterval(refreshInterval)
    }
    
    func updateAutoLaunch(enabled: Bool) {
        autoLaunchEnabled = enabled
        userDefaults.set(enabled, forKey: Constants.UserDefaultsKeys.autoLaunch)
        appState.updateAutoLaunch(enabled: enabled)
    }
    
    func updateNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        userDefaults.set(enabled, forKey: Constants.UserDefaultsKeys.notificationsEnabled)
    }
    
    func updateGroupingEnabled(_ enabled: Bool) {
        groupingEnabled = enabled
        userDefaults.set(enabled, forKey: Constants.UserDefaultsKeys.groupingEnabled)
    }
    
    func updateShowOnlyUnread(_ enabled: Bool) {
        showOnlyUnread = enabled
        userDefaults.set(enabled, forKey: Constants.UserDefaultsKeys.showOnlyUnread)
    }
    
    func updateTheme(_ newTheme: AppTheme) {
        theme = newTheme
        userDefaults.set(newTheme.rawValue, forKey: Constants.UserDefaultsKeys.theme)
    }
    
    func updateFontSize(_ size: FontSize) {
        fontSize = size
        userDefaults.set(size.rawValue, forKey: Constants.UserDefaultsKeys.fontSize)
    }
    
    private func loadSettings() {
        refreshInterval = userDefaults.double(forKey: Constants.UserDefaultsKeys.refreshInterval)
        if refreshInterval == 0 {
            refreshInterval = Constants.defaultRefreshInterval
        }
        
        autoLaunchEnabled = userDefaults.bool(forKey: Constants.UserDefaultsKeys.autoLaunch)
        notificationsEnabled = userDefaults.object(forKey: Constants.UserDefaultsKeys.notificationsEnabled) as? Bool ?? true
        groupingEnabled = userDefaults.object(forKey: Constants.UserDefaultsKeys.groupingEnabled) as? Bool ?? true
        showOnlyUnread = userDefaults.bool(forKey: Constants.UserDefaultsKeys.showOnlyUnread)
        
        if let themeRaw = userDefaults.string(forKey: Constants.UserDefaultsKeys.theme),
           let themeValue = AppTheme(rawValue: themeRaw) {
            theme = themeValue
        }
        
        if let fontSizeRaw = userDefaults.string(forKey: Constants.UserDefaultsKeys.fontSize),
           let fontSizeValue = FontSize(rawValue: fontSizeRaw) {
            fontSize = fontSizeValue
        }
    }
}

enum AppTheme: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .light: return String(localized: "settings.theme.light")
        case .dark: return String(localized: "settings.theme.dark")
        case .system: return String(localized: "settings.theme.system")
        }
    }
}

enum FontSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    
    var displayName: String {
        switch self {
        case .small: return String(localized: "settings.fontSize.small")
        case .medium: return String(localized: "settings.fontSize.medium")
        case .large: return String(localized: "settings.fontSize.large")
        }
    }
    
    var value: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 14
        case .large: return 16
        }
    }
}

