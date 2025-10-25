import Foundation

struct HTMLCleaner {
    /// Удаляет HTML-теги из строки и декодирует HTML-сущности
    static func cleanHTML(_ htmlString: String) -> String {
        var cleaned = htmlString
        
        // Удаляем HTML-теги
        cleaned = cleaned.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        
        // Декодируем HTML-сущности
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&lt;", with: "<")
        cleaned = cleaned.replacingOccurrences(of: "&gt;", with: ">")
        cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "&#39;", with: "'")
        
        // Убираем лишние пробелы и переносы строк
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    /// Извлекает текст из HTML-ссылок, оставляя только текст без тегов
    static func extractTextFromLinks(_ htmlString: String) -> String {
        var cleaned = htmlString
        
        // Заменяем ссылки на их текстовое содержимое
        cleaned = cleaned.replacingOccurrences(of: #"<a[^>]*>([^<]+)</a>"#, with: "$1", options: .regularExpression)
        
        return cleanHTML(cleaned)
    }
    
    /// Обрабатывает упоминания (mentions) - заменяет на обычный текст
    static func processMentions(_ htmlString: String) -> String {
        var cleaned = htmlString
        
        // Заменяем megaplan:mention теги на обычный текст
        cleaned = cleaned.replacingOccurrences(of: #"<megaplan:mention[^>]*>([^<]+)</megaplan:mention>"#, with: "$1", options: .regularExpression)
        
        return cleaned
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
