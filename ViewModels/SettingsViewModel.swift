import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var notificationsEnabled: Bool = true
    @Published var groupingEnabled: Bool = true
    @Published var showOnlyUnread: Bool = false
    @Published var theme: AppTheme = .system
    @Published var fontSize: FontSize = .medium

    let appState: AppState
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    
    init(appState: AppState, userDefaults: UserDefaults = .standard) {
        self.appState = appState
        self.userDefaults = userDefaults

        // Загружаем настройки
        loadSettings()
    }
    
    func updateRefreshInterval(_ interval: Double) {
        let validInterval = max(15, interval)
        userDefaults.set(validInterval, forKey: Constants.UserDefaultsKeys.refreshInterval)
        appState.updateRefreshInterval(validInterval)
    }

    func updateAutoLaunch(enabled: Bool) {
        userDefaults.set(enabled, forKey: Constants.UserDefaultsKeys.autoLaunch)
        appState.updateAutoLaunch(enabled: enabled)
    }
    
    func updateNotificationsEnabled(_ enabled: Bool) {
        updateSetting(enabled, key: Constants.UserDefaultsKeys.notificationsEnabled) {
            notificationsEnabled = $0
        }
    }

    func updateGroupingEnabled(_ enabled: Bool) {
        updateSetting(enabled, key: Constants.UserDefaultsKeys.groupingEnabled) {
            groupingEnabled = $0
        }
    }

    func updateShowOnlyUnread(_ enabled: Bool) {
        updateSetting(enabled, key: Constants.UserDefaultsKeys.showOnlyUnread) {
            showOnlyUnread = $0
        }
    }

    func updateTheme(_ newTheme: AppTheme) {
        updateSetting(newTheme.rawValue, key: Constants.UserDefaultsKeys.theme) { _ in
            theme = newTheme
        }
    }

    func updateFontSize(_ size: FontSize) {
        updateSetting(size.rawValue, key: Constants.UserDefaultsKeys.fontSize) { _ in
            fontSize = size
        }
    }

    private func updateSetting<T>(_ newValue: T, key: String, update: (T) -> Void) {
        update(newValue)
        userDefaults.set(newValue, forKey: key)
    }
    
    private func loadSettings() {
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

