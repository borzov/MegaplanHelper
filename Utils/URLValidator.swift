import Foundation

/// Centralized URL validation and normalization utility
struct URLValidator {

    // MARK: - Public Methods

    /// Normalizes protocol-relative URLs (//example.com) to HTTPS
    /// - Parameter urlString: URL string that may be protocol-relative
    /// - Returns: Normalized URL or nil if invalid
    static func normalizeURL(_ urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Добавляем https: к protocol-relative URLs
        let normalized = trimmed.hasPrefix("//") ? "https:\(trimmed)" : trimmed
        return URL(string: normalized)
    }

    /// Validates a domain string and returns a safe base URL
    /// Includes SSRF protection against internal/metadata endpoints
    /// - Parameter domain: Domain string (e.g., "company.megaplan.ru")
    /// - Returns: Validated HTTPS URL or nil if invalid/blocked
    static func validateDomain(_ domain: String) -> URL? {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // Добавляем схему если отсутствует
        let urlString: String
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            urlString = trimmed
        } else {
            urlString = "https://\(trimmed)"
        }

        // Парсим через URLComponents для корректной валидации
        guard var components = URLComponents(string: urlString) else {
            AppLogger.warning("Invalid URL format: \(domain)")
            return nil
        }

        // Принудительно HTTPS
        if components.scheme == "http" {
            components.scheme = "https"
        }

        // Проверяем что схема HTTPS
        guard components.scheme == "https" else {
            AppLogger.warning("Blocked non-HTTPS scheme: \(domain)")
            return nil
        }

        // Извлекаем и проверяем хост
        guard let host = components.host, !host.isEmpty else {
            AppLogger.warning("No host in URL: \(domain)")
            return nil
        }

        // Блокируем URL с query/fragment (потенциальная инъекция)
        if components.query != nil || components.fragment != nil {
            AppLogger.warning("Blocked URL with query/fragment: \(domain)")
            return nil
        }

        // Блокируем URL с credentials (username:password@host)
        if components.user != nil || components.password != nil {
            AppLogger.warning("Blocked URL with credentials: \(domain)")
            return nil
        }

        // SSRF защита: проверяем хост
        if isBlockedHost(host) {
            AppLogger.warning("Blocked potentially unsafe domain: \(domain)")
            return nil
        }

        // Конструируем чистый URL только со схемой и хостом
        var cleanComponents = URLComponents()
        cleanComponents.scheme = "https"
        cleanComponents.host = host
        cleanComponents.port = components.port

        return cleanComponents.url
    }

    // MARK: - SSRF Protection

    /// Cached blocked IP prefixes for SSRF protection
    private static let blockedIPPrefixes: [String] = [
        "127.", "0.0.0.0", "0.",       // Loopback и zero адреса
        "10.",                          // Class A private
        "172.16.", "172.17.", "172.18.", "172.19.",
        "172.20.", "172.21.", "172.22.", "172.23.",
        "172.24.", "172.25.", "172.26.", "172.27.",
        "172.28.", "172.29.", "172.30.", "172.31.",  // Class B private
        "192.168.",                     // Class C private
        "169.254.",                     // Link-local
        "224.", "225.", "226.", "227.", "228.", "229.",
        "230.", "231.", "232.", "233.", "234.", "235.",
        "236.", "237.", "238.", "239.",  // Multicast
        "255."                          // Broadcast
    ]

    /// Cached blocked IPv6 patterns for SSRF protection
    private static let blockedIPv6Patterns: [String] = [
        "::1", "[::1]",           // IPv6 loopback
        "fe80:", "[fe80:",        // Link-local
        "fc00:", "[fc00:",        // Unique local
        "fd00:", "[fd00:"         // Unique local
    ]

    /// Cached metadata service hosts (Set для O(1) lookup)
    private static let metadataHosts: Set<String> = [
        "169.254.169.254",            // AWS/GCP/Azure metadata
        "metadata.google.internal",
        "metadata.goog"
    ]

    /// Checks if host matches any blocked pattern for SSRF protection
    static func isBlockedHost(_ host: String) -> Bool {
        let lowercasedHost = host.lowercased()

        // Блокируем localhost варианты
        if lowercasedHost == "localhost" ||
           lowercasedHost.hasSuffix(".localhost") ||
           lowercasedHost == "localhost.localdomain" {
            return true
        }

        // Блокируем IP адреса из приватных диапазонов
        for prefix in blockedIPPrefixes {
            if lowercasedHost.hasPrefix(prefix) {
                return true
            }
        }

        // Блокируем IPv6 localhost и приватные адреса
        for pattern in blockedIPv6Patterns {
            if lowercasedHost.hasPrefix(pattern) || lowercasedHost.contains(pattern) {
                return true
            }
        }

        // Блокируем metadata service endpoints (O(1) lookup)
        if metadataHosts.contains(lowercasedHost) {
            return true
        }

        return false
    }
}
