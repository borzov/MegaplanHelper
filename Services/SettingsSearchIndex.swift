import Foundation

/// Static keyword index mapping search terms to settings sections.
/// Bilingual: ru + en keywords for each section.
final class SettingsSearchIndex {
    static let shared = SettingsSearchIndex()

    private let index: [SettingsSection: Set<String>] = [
        .account: ["account", "аккаунт", "login", "логин", "password", "пароль",
                   "domain", "домен", "avatar", "аватар", "sign in", "войти",
                   "logout", "выход"],
        .sync: ["sync", "синхронизация", "refresh", "обновление", "interval",
                "интервал", "auto launch", "автозапуск", "startup", "unread",
                "непрочитанные"],
        .appearance: ["appearance", "внешний вид", "theme", "тема", "dark", "тёмная",
                      "light", "светлая", "font", "шрифт", "size", "размер"],
        .notifications: ["notifications", "уведомления", "grouping", "группировка",
                         "test", "тест"],
        .shortcuts: ["shortcuts", "горячие клавиши", "hotkey", "keyboard",
                     "клавиатура", "cmd", "опция"],
        .storage: ["storage", "хранилище", "cache", "кэш", "clear", "очистить",
                   "reset", "сброс", "export", "экспорт", "import", "импорт",
                   "size", "размер"],
        .about: ["about", "о программе", "version", "версия", "help", "помощь",
                 "github", "feedback", "отзыв", "license", "лицензия"]
    ]

    private init() {}

    /// Returns sections whose index contains any token from the query.
    /// Empty query returns all sections. Tokens shorter than 2 characters are
    /// ignored to prevent single-letter substring matches flooding results.
    func search(_ query: String) -> [SettingsSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty {
            return SettingsSection.allCases
        }
        let tokens = trimmed.split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 }
        if tokens.isEmpty {
            return SettingsSection.allCases
        }
        return SettingsSection.allCases.filter { section in
            guard let keywords = index[section] else { return false }
            return tokens.contains { token in
                keywords.contains { $0.contains(token) }
            }
        }
    }
}
