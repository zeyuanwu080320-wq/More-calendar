import Foundation

/// Date parsing at the model boundary. We only accept unambiguous numeric dates
/// with a year. Missing years, lunar dates, natural-language weekdays, and other
/// ambiguous forms remain nil and must be filled in by the user.
public enum FlexibleDateParser {
    public struct Result: Equatable, Sendable {
        public let date: Date
        public let isDateOnly: Bool
        public let hadExplicitTimeZone: Bool
    }

    private static let internetFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let localPatterns = [
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd HH:mm",
        "yyyy/MM/dd",
        "yyyy年M月d日 HH:mm:ss",
        "yyyy年M月d日 HH:mm",
        "yyyy年M月d日"
    ]

    public static func parse(_ raw: String?, timeZone: TimeZone = .current) -> Result? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let dateOnly = value.range(of: #"^\d{4}-\d{1,2}-\d{1,2}$"#, options: .regularExpression) != nil
            || value.range(of: #"^\d{4}/\d{1,2}/\d{1,2}$"#, options: .regularExpression) != nil
            || value.range(of: #"^\d{4}年\d{1,2}月\d{1,2}日$"#, options: .regularExpression) != nil
        let hasExplicitTimeZone = value.range(of: #"(Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) != nil

        if let date = internetFormatterWithFractional.date(from: value) {
            return Result(date: date, isDateOnly: dateOnly, hadExplicitTimeZone: hasExplicitTimeZone)
        }
        if let date = internetFormatter.date(from: value) {
            return Result(date: date, isDateOnly: dateOnly, hadExplicitTimeZone: hasExplicitTimeZone)
        }

        for pattern in localPatterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            formatter.isLenient = false
            if let date = formatter.date(from: value) {
                return Result(date: date, isDateOnly: dateOnly, hadExplicitTimeZone: hasExplicitTimeZone)
            }
        }
        return nil
    }

    public static func isoString(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
