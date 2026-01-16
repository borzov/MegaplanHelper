import Foundation

struct HTMLCleaner {
    // MARK: - Cached Regex Patterns

    /// Cached regex for removing HTML tags
    private static let htmlTagsRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"<[^>]+>"#, options: [])
    }()

    /// Cached regex for collapsing whitespace
    private static let whitespaceRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\s+"#, options: [])
    }()

    /// Cached regex for extracting text from links
    private static let linksRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"<a[^>]*>([^<]+)</a>"#, options: [])
    }()

    /// Cached regex for processing mentions
    private static let mentionsRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"<megaplan:mention[^>]*>([^<]+)</megaplan:mention>"#, options: [])
    }()

    // MARK: - Helper Methods

    /// Apply regex replacement using cached NSRegularExpression
    private static func applyRegex(_ regex: NSRegularExpression?, to string: String, replacement: String) -> String {
        guard let regex = regex else { return string }
        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: replacement)
    }

    // MARK: - Public API

    /// Удаляет HTML-теги из строки и декодирует HTML-сущности
    static func cleanHTML(_ htmlString: String) -> String {
        var cleaned = htmlString

        // Удаляем HTML-теги (using cached regex)
        cleaned = applyRegex(htmlTagsRegex, to: cleaned, replacement: "")

        // Decode HTML entities (IMPORTANT: &amp; must be decoded LAST to prevent XSS via double encoding)
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&lt;", with: "<")
        cleaned = cleaned.replacingOccurrences(of: "&gt;", with: ">")
        cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "&#39;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")

        // Убираем лишние пробелы и переносы строк (using cached regex)
        cleaned = applyRegex(whitespaceRegex, to: cleaned, replacement: " ")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
    
    /// Извлекает текст из HTML-ссылок, оставляя только текст без тегов
    static func extractTextFromLinks(_ htmlString: String) -> String {
        // Заменяем ссылки на их текстовое содержимое (using cached regex)
        let cleaned = applyRegex(linksRegex, to: htmlString, replacement: "$1")
        return cleanHTML(cleaned)
    }

    /// Обрабатывает упоминания (mentions) - заменяет на обычный текст
    static func processMentions(_ htmlString: String) -> String {
        // Заменяем megaplan:mention теги на обычный текст (using cached regex)
        return applyRegex(mentionsRegex, to: htmlString, replacement: "$1")
    }
    
    /// Полная очистка HTML с обработкой всех специальных случаев
    static func fullClean(_ htmlString: String) -> String {
        var cleaned = htmlString
        
        // Сначала обрабатываем упоминания
        cleaned = processMentions(cleaned)
        
        // Затем извлекаем текст из ссылок
        cleaned = extractTextFromLinks(cleaned)
        
        // И наконец очищаем от всех остальных HTML-тегов
        cleaned = cleanHTML(cleaned)
        
        return cleaned
    }
}
