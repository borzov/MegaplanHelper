import Foundation
import OSLog

enum Constants {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.ruvents.MegaplanMenuBarApp"
    static let defaultRefreshInterval: TimeInterval = 60

    /// Network request timeouts
    enum NetworkTimeouts {
        static let requestTimeout: TimeInterval = 30
        static let resourceTimeout: TimeInterval = 60
    }
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

    // Buffering configuration
    private static var logBuffer: [String] = []
    private static let bufferSize = 10
    private static let maxLogSize: Int64 = 5 * 1024 * 1024  // 5 MB
    private static var lastFlushTime = Date()
    private static let maxFlushInterval: TimeInterval = 5.0  // Flush every 5 seconds

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

    /// Flushes any remaining buffered log entries
    /// Should be called before app termination
    static func flush() {
        logQueue.sync {
            flushLogBuffer()
        }
    }

    private static func writeToFile(level: String, message: String) {
        logQueue.async {
            let logEntry = "[\(dateFormatter.string(from: Date()))] [\(level)] \(message)\n"
            logBuffer.append(logEntry)

            // Flush buffer if it's full or enough time has passed
            let timeSinceLastFlush = Date().timeIntervalSince(lastFlushTime)
            if logBuffer.count >= bufferSize || timeSinceLastFlush >= maxFlushInterval {
                flushLogBuffer()
            }
        }
    }

    private static func flushLogBuffer() {
        guard !logBuffer.isEmpty else { return }

        let logURL = Constants.logFileURL
        let directory = logURL.deletingLastPathComponent()

        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create log directory: \(error.localizedDescription, privacy: .public)")
                logBuffer.removeAll()
                return
            }
        }

        // Rotate log if too large
        if FileManager.default.fileExists(atPath: logURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           let fileSize = attrs[.size] as? Int64,
           fileSize > maxLogSize {
            rotateLog(at: logURL)
        }

        // Write buffered entries
        let combined = logBuffer.joined()
        if let data = combined.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                FileManager.default.createFile(atPath: logURL.path, contents: data)
            }
        }

        logBuffer.removeAll()
        lastFlushTime = Date()
    }

    private static func rotateLog(at logURL: URL) {
        let backupURL = logURL.deletingPathExtension().appendingPathExtension("old.log")

        // Remove old backup if exists
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
        }

        // Move current log to backup
        try? FileManager.default.moveItem(at: logURL, to: backupURL)

        logger.info("Log file rotated")
    }
}
