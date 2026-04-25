import Foundation

/// Centralized cached `DateFormatter` / `RelativeDateTimeFormatter` instances.
///
/// All UI surfaces should reuse these instead of constructing formatters per render
/// (formatter creation is expensive and the project guideline mandates caching).
enum DateFormatters {
    private static let calendar = Calendar.current

    /// `25 апр` / `25 апр 2025` for absolute dates older than a week.
    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static let dayMonthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    /// `12:48` for same-day timestamps.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.unitsStyle = .short
        return formatter
    }()

    /// User-friendly relative timestamp:
    /// - < 1 минуты → "только что"
    /// - < 1 часа → "X мин назад"
    /// - сегодня → "HH:mm"
    /// - вчера → "вчера"
    /// - < 7 дней → день недели
    /// - этот год → "d MMM"
    /// - иначе → "d MMM yyyy"
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return String(localized: "tasks.time.justNow")
        }
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return String(format: String(localized: "tasks.time.minutesAgo"), minutes)
        }

        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "tasks.time.yesterday")
        }

        let daysBetween = calendar.dateComponents([.day], from: date, to: now).day ?? Int.max
        if daysBetween < 7 {
            return weekdayFormatter.string(from: date).capitalized(with: Locale(identifier: "ru_RU"))
        }

        let nowYear = calendar.component(.year, from: now)
        let dateYear = calendar.component(.year, from: date)
        if nowYear == dateYear {
            return dayMonthFormatter.string(from: date)
        }
        return dayMonthYearFormatter.string(from: date)
    }

    /// Absolute date label used in the secondary "создано N" line.
    static func absoluteShort(_ date: Date, now: Date = Date()) -> String {
        let nowYear = calendar.component(.year, from: now)
        let dateYear = calendar.component(.year, from: date)
        return nowYear == dateYear
            ? dayMonthFormatter.string(from: date)
            : dayMonthYearFormatter.string(from: date)
    }

    /// Returns the date-bucket section title for grouping a list of items by day.
    enum Bucket {
        case today, yesterday, thisWeek, earlier
        var title: String {
            switch self {
            case .today: return String(localized: "notifications.group.today")
            case .yesterday: return String(localized: "notifications.group.yesterday")
            case .thisWeek: return String(localized: "notifications.group.thisWeek")
            case .earlier: return String(localized: "notifications.group.earlier")
            }
        }
    }

    static func bucket(for date: Date, now: Date = Date()) -> Bucket {
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        let daysBetween = calendar.dateComponents([.day], from: date, to: now).day ?? Int.max
        if daysBetween < 7 { return .thisWeek }
        return .earlier
    }
}
