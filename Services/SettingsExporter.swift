import Foundation

/// Exports/imports a curated subset of settings as a portable JSON snapshot.
/// Excludes credentials, transient state and machine-specific keys.
final class SettingsExporter {
    enum ExportError: Error {
        case encodingFailed
        case invalidJSON
        case unknownKey(String)
    }

    /// Whitelist of UserDefaults keys safe for export. Add new entries as features land.
    static let exportableKeys: [String] = [
        "refreshInterval",
        "showOnlyUnread",
        "notificationsEnabled",
        "groupingEnabled",
        "appTheme",
        "fontSize",
        "autoLaunchEnabled"
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns a JSON string representing all whitelisted keys present in defaults.
    func export() throws -> String {
        var snapshot: [String: Any] = [:]
        for key in Self.exportableKeys {
            if let value = defaults.object(forKey: key) {
                snapshot[key] = value
            }
        }
        let data = try JSONSerialization.data(
            withJSONObject: snapshot,
            options: [.prettyPrinted, .sortedKeys]
        )
        guard let json = String(data: data, encoding: .utf8) else {
            throw ExportError.encodingFailed
        }
        return json
    }

    /// Restores whitelisted keys from JSON string. Unknown keys are ignored silently.
    func importing(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw ExportError.invalidJSON
        }
        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = parsed as? [String: Any] else {
            throw ExportError.invalidJSON
        }
        for key in Self.exportableKeys {
            if let value = dict[key] {
                defaults.set(value, forKey: key)
            }
        }
    }
}
