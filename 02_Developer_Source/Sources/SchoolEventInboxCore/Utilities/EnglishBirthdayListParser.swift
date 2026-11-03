import Foundation

/// Deterministic safety net for an entire input made of lines such as:
/// "December 8 - Hayeon". The model sometimes labels these as "other"; this
/// parser only activates when every content line matches that exact shape.
public enum EnglishBirthdayListParser {
    private static let monthNumbers: [String: Int] = [
        "january": 1, "jan": 1,
        "february": 2, "feb": 2,
        "march": 3, "mar": 3,
        "april": 4, "apr": 4,
        "may": 5,
        "june": 6, "jun": 6,
        "july": 7, "jul": 7,
        "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9,
        "october": 10, "oct": 10,
        "november": 11, "nov": 11,
        "december": 12, "dec": 12
    ]

    public static func parse(
        text: String,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> [ParsedEvent]? {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isWrapperLine($0) }
        guard !lines.isEmpty else { return nil }

        let expression = try? NSRegularExpression(
            pattern: #"^\s*([A-Za-z]+)\s+(\d{1,2})(?:\s*,?\s*(\d{4}))?\s*[-–—]\s*(.+?)\s*$"#
        )
        guard let expression else { return nil }

        var events: [ParsedEvent] = []
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = expression.firstMatch(in: line, range: range),
                  let monthRange = Range(match.range(at: 1), in: line),
                  let dayRange = Range(match.range(at: 2), in: line),
                  let nameRange = Range(match.range(at: 4), in: line) else {
                return nil
            }
            let monthName = String(line[monthRange]).lowercased()
            guard let month = monthNumbers[monthName],
                  let day = Int(line[dayRange]) else { return nil }
            let name = String(line[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            var year = calendar.component(.year, from: now)
            var hadYear = false
            if match.range(at: 3).location != NSNotFound,
               let yearRange = Range(match.range(at: 3), in: line),
               let parsedYear = Int(line[yearRange]) {
                year = parsedYear
                hadYear = true
            }
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = 0
            components.minute = 0
            components.second = 0
            components.timeZone = timeZone
            guard let start = calendar.date(from: components) else { return nil }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = timeZone
            let notes = hadYear ? "纯日期姓名名单，按生日处理。" : "缺年份，默认今年；纯日期姓名名单，按生日处理。"

            events.append(ParsedEvent(
                type: .birthday,
                title: "\(name) 生日",
                start: formatter.string(from: start),
                end: nil,
                allDay: true,
                location: nil,
                confidence: 0.95,
                evidence: line,
                needsConfirmation: true,
                notes: notes
            ))
        }
        return events.isEmpty ? nil : events
    }

    private static func isWrapperLine(_ line: String) -> Bool {
        line.hasPrefix("【邮件正文】") || line.hasPrefix("【图片 ")
    }
}
