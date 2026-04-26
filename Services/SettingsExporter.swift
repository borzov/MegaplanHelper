import Foundation

/// Exports/imports a curated subset of settings as a portable JSON snapshot.
/// Excludes credentials, transient state and machine-specific keys.
final class SettingsExporter {
    enum ExportError: Error {
        case encodingFailed
        case invalidJSON
        case invalidValueType(key: String, expected: String)
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

    /// Type validation for imported values. Maps each whitelisted key to the
    /// expected Foundation runtime type (NSNumber covers Bool/Int/Double in JSON).
    private static let expectedTypes: [String: AnyClass] = [
        "refreshInterval": NSNumber.self,
        "showOnlyUnread": NSNumber.self,
        "notificationsEnabled": NSNumber.self,
        "groupingEnabled": NSNumber.self,
        "appTheme": NSString.self,
        "fontSize": NSString.self,
        "autoLaunchEnabled": NSNumber.self
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

    /// Restores whitelisted keys from JSON string. Unknown keys (not in
    /// `exportableKeys`) are silently ignored. If any whitelisted key has
    /// the wrong runtime type, throws `ExportError.invalidValueType`
    /// without mutating UserDefaults (validate-then-apply).
    func importing(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw ExportError.invalidJSON
        }
        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = parsed as? [String: Any] else {
            throw ExportError.invalidJSON
        }

        // Validate all values first to prevent partial mutation on bad input.
        var validated: [(String, Any)] = []
        for key in Self.exportableKeys {
            guard let value = dict[key] else { continue }
            guard let expectedType = Self.expectedTypes[key] else { continue }
            let object = value as AnyObject
            guard object.isKind(of: expectedType) else {
                throw ExportError.invalidValueType(
                    key: key,
                    expected: String(describing: expectedType)
                )
            }
            validated.append((key, value))
        }

        // All values valid — apply atomically.
        for (key, value) in validated {
            defaults.set(value, forKey: key)
        }
    }
}
