import Foundation

public struct DraftSnapshot: Equatable, Sendable {
    public var type: EventType
    public var title: String
    public var start: Date?
    public var end: Date?
    public var allDay: Bool
    public var location: String?
    public var notes: String

    public init(type: EventType, title: String, start: Date?, end: Date?, allDay: Bool, location: String?, notes: String) {
        self.type = type
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
        self.notes = notes
    }
}

public struct CalendarConflict: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarName: String
    public let isAllDay: Bool

    public init(id: String, title: String, start: Date, end: Date, calendarName: String, isAllDay: Bool) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarName = calendarName
        self.isAllDay = isAllDay
    }
}

/// Editable state shown on the confirmation cards. Dates are optional at the
/// user-facing level: an OCR miss leaves `hasStart == false` and cannot be
/// silently turned into today's date.
public struct EventDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var type: EventType
    public var title: String
    public var hasStart: Bool
    public var start: Date
    public var hasEnd: Bool
    public var end: Date
    public var allDay: Bool
    public var location: String
    public var confidence: Double
    public var evidence: String
    public var notes: String
    public var confirmed: Bool
    public var writeAnyway: Bool
    public var isWritten: Bool
    public var conflicts: [CalendarConflict]
    public let original: DraftSnapshot

    public init(
        id: UUID = UUID(),
        type: EventType,
        title: String,
        hasStart: Bool,
        start: Date,
        hasEnd: Bool,
        end: Date,
        allDay: Bool,
        location: String,
        confidence: Double,
        evidence: String,
        notes: String,
        confirmed: Bool = true,
        writeAnyway: Bool = false,
        isWritten: Bool = false,
        conflicts: [CalendarConflict] = [],
        original: DraftSnapshot
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.hasStart = hasStart
        self.start = start
        self.hasEnd = hasEnd
        self.end = end
        self.allDay = allDay
        self.location = location
        self.confidence = confidence
        self.evidence = evidence
        self.notes = notes
        self.confirmed = confirmed
        self.writeAnyway = writeAnyway
        self.isWritten = isWritten
        self.conflicts = conflicts
        self.original = original
    }

    public var validationMessages: [String] {
        var messages: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("标题为空")
        }
        if !hasStart {
            messages.append("需补充开始时间")
        }
        if !confirmed {
            messages.append("尚未确认")
        }
        if hasStart && hasEnd && !allDay && end <= start {
            messages.append("结束时间必须晚于开始时间")
        }
        if hasStart && hasEnd && allDay && Calendar.current.startOfDay(for: end) < Calendar.current.startOfDay(for: start) {
            messages.append("结束日期不能早于开始日期")
        }
        return messages
    }

    public var canWrite: Bool {
        validationMessages.isEmpty
    }

    public var isCritical: Bool {
        type.requiresConfirmation
    }

    /// EventKit uses an exclusive end date for all-day events, and requires a
    /// non-zero duration for timed events. A missing end is deliberately shown
    /// as "+1 小时占位" in the UI rather than being treated as parsed content.
    public func calendarInterval(calendar: Calendar = .current) -> DateInterval {
        let actualStart: Date
        if allDay {
            actualStart = calendar.startOfDay(for: start)
        } else {
            actualStart = start
        }

        if allDay {
            let startDay = calendar.startOfDay(for: start)
            var endDay: Date
            if hasEnd {
                endDay = calendar.startOfDay(for: end)
            } else {
                endDay = startDay
            }
            if endDay <= startDay {
                endDay = calendar.date(byAdding: .day, value: 1, to: startDay) ?? startDay.addingTimeInterval(86_400)
            } else {
                endDay = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay.addingTimeInterval(86_400)
            }
            return DateInterval(start: startDay, end: endDay)
        }

        let actualEnd: Date
        if hasEnd && end > actualStart {
            actualEnd = end
        } else {
            actualEnd = actualStart.addingTimeInterval(3_600)
        }
        return DateInterval(start: actualStart, end: actualEnd)
    }

    public var modifiedFields: [String] {
        var fields: [String] = []
        if original.type != type { fields.append("type") }
        if original.title != title { fields.append("title") }
        let currentStart = hasStart ? start : nil
        if !datesEqual(original.start, currentStart) { fields.append("start") }
        let currentEnd = hasEnd ? end : nil
        if !datesEqual(original.end, currentEnd) { fields.append("end") }
        if original.allDay != allDay { fields.append("allDay") }
        if (original.location ?? "") != location { fields.append("location") }
        if original.notes != notes { fields.append("notes") }
        return fields
    }
}

public enum DraftFactory {
    public static func makeDrafts(
        from events: [ParsedEvent],
        now: Date = Date(),
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> [EventDraft] {
        events.map { makeDraft(from: $0, now: now, timeZone: timeZone, calendar: calendar) }
    }

    public static func makeDraft(
        from event: ParsedEvent,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> EventDraft {
        var notes = event.notes
        let startResult = FlexibleDateParser.parse(event.start, timeZone: timeZone)
        let endResult = FlexibleDateParser.parse(event.end, timeZone: timeZone)

        if event.start == nil {
            notes = ParsedEventSanitizer.appendNote("未识别到开始时间，需人工补充。", to: notes)
        } else if startResult == nil {
            notes = ParsedEventSanitizer.appendNote("开始时间无法可靠解析，已置空，需人工补充。", to: notes)
        }
        if event.end != nil && endResult == nil {
            notes = ParsedEventSanitizer.appendNote("结束时间无法可靠解析，已置空。", to: notes)
        }

        if let startResult, !startResult.hadExplicitTimeZone && !startResult.isDateOnly {
            notes = ParsedEventSanitizer.appendNote(
                "原始时间未标明时区，已按本机时区（\(timeZone.identifier)）解释，请确认。",
                to: notes
            )
        }

        var allDay = event.allDay
        if let startResult, startResult.isDateOnly && !event.allDay {
            allDay = true
            notes = ParsedEventSanitizer.appendNote("原文只有日期没有具体时间，已设为全天，请确认。", to: notes)
        }

        let defaultStart = nextHour(from: now, calendar: calendar)
        let start = startResult?.date ?? (allDay ? calendar.startOfDay(for: now) : defaultStart)
        let hasStart = startResult != nil

        var end = endResult?.date ?? start.addingTimeInterval(allDay ? 0 : 3_600)
        var hasEnd = endResult != nil
        if allDay {
            end = calendar.startOfDay(for: end)
            if hasStart {
                let startDay = calendar.startOfDay(for: start)
                if hasEnd && end < startDay {
                    notes = ParsedEventSanitizer.appendNote("结束日期早于开始日期，请核对。", to: notes)
                }
            }
        }
        if !hasStart {
            hasEnd = false
            end = start.addingTimeInterval(allDay ? 0 : 3_600)
        }

        let location = event.location ?? ""
        let snapshot = DraftSnapshot(
            type: event.type,
            title: event.title,
            start: hasStart ? start : nil,
            end: hasEnd ? end : nil,
            allDay: allDay,
            location: location,
            notes: notes
        )

        return EventDraft(
            type: event.type,
            title: event.title,
            hasStart: hasStart,
            start: start,
            hasEnd: hasEnd,
            end: end,
            allDay: allDay,
            location: location,
            confidence: event.confidence,
            evidence: event.evidence,
            notes: notes,
            confirmed: true,
            original: snapshot
        )
    }

    private static func nextHour(from date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        var next = calendar.date(from: components) ?? date
        next = calendar.date(byAdding: .hour, value: 1, to: next) ?? date.addingTimeInterval(3_600)
        return next
    }
}

private func datesEqual(_ lhs: Date?, _ rhs: Date?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case let (lhs?, rhs?):
        return abs(lhs.timeIntervalSince(rhs)) < 0.5
    default:
        return false
    }
}

public enum ConflictDetector {
    public static func overlaps(_ lhs: DateInterval, _ rhs: DateInterval) -> Bool {
        lhs.start < rhs.end && rhs.start < lhs.end
    }
}
