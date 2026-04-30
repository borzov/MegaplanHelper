import Foundation

/// Russian-aware pluralization helpers shared by the Tasks and Notifications tabs.
/// Russian uses three plural forms (one / few / many); the choice depends on
/// the last two digits of the count (CLDR ru rule).
enum Pluralization {
    /// Picks the plural form for `count` and returns the format string ready for
    /// `String(format:)` interpolation. Each format MUST contain a single `%d`
    /// placeholder.
    static func russian(count: Int, one: String, few: String, many: String) -> String {
        return String(format: form(count: count, one: one, few: few, many: many), count)
    }

    /// Returns the chosen plural form (no `%d` substitution) — useful when the
    /// caller already owns the surrounding format ("%d %@", "Найдено: %d %@", etc).
    static func form(count: Int, one: String, few: String, many: String) -> String {
        let absCount = abs(count)
        let mod10 = absCount % 10
        let mod100 = absCount % 100
        if (11...19).contains(mod100) { return many }
        switch mod10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }

    /// "1 комментарий", "3 комментария", "5 комментариев". Resolves the noun via
    /// shared `comments.*` keys so Tasks and Notifications stay in sync.
    static func commentsLabel(_ count: Int) -> String {
        let noun = form(count: count,
                        one: String(localized: "comments.one"),
                        few: String(localized: "comments.few"),
                        many: String(localized: "comments.many"))
        return String(format: String(localized: "comments.format"), count, noun)
    }

    /// Short segment for unread count in the "total · …" task badge (Russian plural rules, localized strings).
    static func newUnreadCommentsSegment(_ count: Int) -> String {
        russian(count: count,
                one: String(localized: "tasks.row.comments.new.one"),
                few: String(localized: "tasks.row.comments.new.few"),
                many: String(localized: "tasks.row.comments.new.many"))
    }
}
