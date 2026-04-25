import Foundation

/// Logical groups in the Settings sidebar.
enum SettingsGroup: String, CaseIterable, Identifiable {
    case general
    case personalization
    case advanced
    case about

    var id: String { rawValue }

    var titleKey: LocalizedStringResource {
        switch self {
        case .general: return "settings.group.general"
        case .personalization: return "settings.group.personalization"
        case .advanced: return "settings.group.advanced"
        case .about: return "settings.group.about"
        }
    }
}

/// All available settings sections, in display order within their group.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case account
    case sync
    case appearance
    case notifications
    case shortcuts
    case storage
    case about

    var id: String { rawValue }

    var group: SettingsGroup {
        switch self {
        case .account, .sync: return .general
        case .appearance, .notifications: return .personalization
        case .shortcuts, .storage: return .advanced
        case .about: return .about
        }
    }

    var titleKey: LocalizedStringResource {
        switch self {
        case .account: return "settings.section.account"
        case .sync: return "settings.section.sync"
        case .appearance: return "settings.section.appearance"
        case .notifications: return "settings.section.notifications"
        case .shortcuts: return "settings.section.shortcuts"
        case .storage: return "settings.section.storage"
        case .about: return "settings.section.about"
        }
    }

    /// SF Symbol name for the sidebar icon.
    var iconName: String {
        switch self {
        case .account: return "person.crop.circle"
        case .sync: return "arrow.clockwise"
        case .appearance: return "paintpalette"
        case .notifications: return "bell.badge"
        case .shortcuts: return "keyboard"
        case .storage: return "externaldrive.badge.timemachine"
        case .about: return "info.circle"
        }
    }

    /// Tint applied to the icon "tile" in the sidebar.
    var tint: TintColor {
        switch self {
        case .account: return .purple
        case .sync: return .blue
        case .appearance: return .red
        case .notifications: return .orange
        case .shortcuts: return .grey
        case .storage: return .green
        case .about: return .grey
        }
    }

    enum TintColor: String { case purple, blue, red, orange, grey, green }
}
