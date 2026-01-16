import Foundation
import OSLog

enum Constants {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.ruvents.MegaplanMenuBarApp"
    static let defaultRefreshInterval: TimeInterval = 60
    static let logFileURL: URL = {
        let logsDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Logs", isDirectory: true) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return logsDirectory.appendingPathComponent("MegaplanApp.log", isDirectory: false)
    }()
    static let sparkleFeedURL = URL(string: "https://example.com/megaplan/sparkle/appcast.xml")

    enum UserDefaultsKeys {
        static let domain = "megaplan.domain"
        static let username = "megaplan.username"
        static let refreshInterval = "megaplan.refreshInterval"
        static let autoLaunch = "megaplan.autoLaunch"
        static let notificationsEnabled = "megaplan.notificationsEnabled"
        static let groupingEnabled = "megaplan.groupingEnabled"
        static let showOnlyUnread = "megaplan.showOnlyUnread"
        static let theme = "megaplan.theme"
        static let fontSize = "megaplan.fontSize"
        static let visitedNotificationIds = "megaplan.visitedNotificationIds"
    }

    enum Keychain {
        static let service = "com.megaplan.credentials"
        static let tokenAccount = "accessToken"

        static func passwordAccount(for username: String, domain: String) -> String {
            "\(username)@\(domain)"
        }
    }

    static let loginItemIdentifier = "com.ruvents.MegaplanMenuBarApp.LoginItem"

    /// Certificate pinning configuration for Megaplan API
    /// Hashes obtained from demo.megaplan.ru certificate chain
    enum CertificatePinning {
        /// SHA256 hashes of public keys in the certificate chain
        /// - Intermediate CA: GlobalSign GCC R6 AlphaSSL CA 2023
        /// - Root CA: GlobalSign Root CA - R6
        static let pinnedPublicKeyHashes: Set<String> = [
            "JdFERRONSeokpPRwHKoZgZPPGO+7YwoMHGHoe1BAq3c=",  // Intermediate CA (primary)
            "aCdH+LpiG4fN07wpXtXKvOciocDANj0daLOJKNJ4fx4="   // Root CA (backup)
        ]

        /// Whether certificate pinning is enabled
        /// Set to false for debugging with proxy tools like Charles
        #if DEBUG
        static let isEnabled = false
        #else
        static let isEnabled = true
        #endif
    }

    /// Набор прав доступа, наличие хотя бы одного из которых указывает на роль администратора
    enum AdminPermissions {
        static let permissions: Set<String> = [
            "settings_setting_employees_rights",
            "settings_setting_system",
            "can_edit_employees_settings",
            "project_admin",
            "can_install_application"
        ]
        
        /// Проверяет, является ли пользователь администратором на основе списка прав
        /// - Parameter userPermissions: Массив прав пользователя из `possibleActions`
        /// - Returns: `true`, если пользователь имеет хотя бы одно административное право
        static func isAdministrator(_ userPermissions: [String]?) -> Bool {
            guard let userPermissions = userPermissions else {
                return false
            }
            return userPermissions.contains { permissions.contains($0) }
        }
    }
}

enum AppLogger {
    private static let logger = Logger(subsystem: Constants.bundleIdentifier, category: "Megaplan")
    private static let logQueue = DispatchQueue(label: "com.ruvents.logger", qos: .utility)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func info(_ message: String) {
        logger.log("\(message, privacy: .public)")
        writeToFile(level: "INFO", message: message)
    }

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        writeToFile(level: "DEBUG", message: message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        writeToFile(level: "ERROR", message: message)
    }
    
    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        writeToFile(level: "WARNING", message: message)
    }

    private static func writeToFile(level: String, message: String) {
        logQueue.async {
            let logEntry = "[\(dateFormatter.string(from: Date()))] [\(level)] \(message)\n"
            guard let data = logEntry.data(using: .utf8) else {
                return
            }

            let logURL = Constants.logFileURL
            let directory = logURL.deletingLastPathComponent()

            if !FileManager.default.fileExists(atPath: directory.path) {
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                } catch {
                    logger.error("Failed to create log directory: \(error.localizedDescription, privacy: .public)")
                    return
                }
            }

            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: data)
            } else {
                do {
                    let handle = try FileHandle(forWritingTo: logURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    logger.error("Failed to append to log file: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
