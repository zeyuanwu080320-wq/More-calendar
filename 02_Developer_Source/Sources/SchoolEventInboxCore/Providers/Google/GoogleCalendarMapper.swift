import Foundation

/// `EventDraft` ↔ Google Calendar 事件资源的纯映射。
///
/// 全部是静态纯函数：没有网络、没有 EventKit，因此可以完整单测。
/// 这里也是"颜色分类型"和"托管标签"的唯一落点——两个约定都不能散落到 Provider 里。
public enum GoogleCalendarMapper {
    /// 我们写在 `extendedProperties.private` 里的标记，用于精确筛选本工具创建的事件。
    public static let managedPropertyKey = "schoolEventInboxManaged"
    public static let typePropertyKey = "schoolEventInboxType"

    // MARK: - 颜色

    /// Google 事件调色板里与 Apple 侧保持一致的近似色。
    /// 11 Tomato(红) / 3 Grape(紫) / 6 Tangerine(橙) / 9 Blueberry(蓝) / 10 Basil(绿)
    public static func colorId(for type: EventType) -> String {
        switch type.managedCalendarBucket {
        case .exam: return "11"
        case .birthday: return "3"
        case .deadline: return "6"
        case .appointment: return "9"
        case .activity, .other: return "10"
        }
    }

    // MARK: - 写

    /// 把一张确认过的草稿映射成 `events.insert` 的请求体。
    public static func makeEventBody(
        from draft: EventDraft,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> GoogleEvent {
        var event = GoogleEvent()
        event.summary = draft.title
        // Google 没有独立的 notes 字段，托管标签必须写进 description，
        // 否则管理面板与删除操作都认不出这是本工具创建的。
        event.notes = ManagedEventMetadata.managedNotes(original: draft.notes, type: draft.type)
        let trimmedLocation = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = trimmedLocation.isEmpty ? nil : trimmedLocation
        event.colorId = colorId(for: draft.type)
        event.extendedProperties = GoogleExtendedProperties(private: [
            managedPropertyKey: "1",
            typePropertyKey: draft.type.rawValue
        ])
        event.transparency = "opaque"

        let interval = draft.calendarInterval(calendar: calendar)
        if draft.allDay || draft.type == .birthday {
            event.start = GoogleEventDateTime(date: GoogleDateCodec.dateOnlyString(interval.start, timeZone: timeZone))
            event.end = GoogleEventDateTime(date: GoogleDateCodec.dateOnlyString(interval.end, timeZone: timeZone))
        } else {
            event.start = GoogleEventDateTime(
                dateTime: GoogleDateCodec.dateTimeString(interval.start, timeZone: timeZone),
                timeZone: timeZone.identifier
            )
            event.end = GoogleEventDateTime(
                dateTime: GoogleDateCodec.dateTimeString(interval.end, timeZone: timeZone),
                timeZone: timeZone.identifier
            )
        }

        if draft.type == .birthday {
            event.recurrence = ["RRULE:FREQ=YEARLY"]
        }
        return event
    }

    // MARK: - 读

    /// 判断一条 Google 事件是否由本工具创建。
    ///
    /// 优先看 `extendedProperties.private`（精确、不受用户改备注影响），
    /// 回退到 description 里的托管标签（兼容"标签被写进 description 但属性丢失"的情况）。
    public static func isManaged(_ event: GoogleEvent) -> Bool {
        if event.extendedProperties?.private?[managedPropertyKey] == "1" { return true }
        return ManagedEventMetadata.isManagedNotes(event.notes)
    }

    public static func eventType(from event: GoogleEvent) -> EventType? {
        if let raw = event.extendedProperties?.private?[typePropertyKey],
           let type = EventType(rawValue: raw) {
            return type
        }
        return ManagedEventMetadata.eventType(fromNotes: event.notes)
    }

    /// 组合成稳定的 `ManagedEvent.id`：`calendarID/eventID`。
    /// Google 的 event id 只在单个日历内唯一，必须带上日历。
    public static func managedEventID(calendarID: String, eventID: String) -> String {
        "\(calendarID)/\(eventID)"
    }

    public static func splitManagedEventID(_ id: String) -> (calendarID: String, eventID: String)? {
        guard let separator = id.firstIndex(of: "/") else { return nil }
        let calendarID = String(id[id.startIndex..<separator])
        let eventID = String(id[id.index(after: separator)...])
        guard !calendarID.isEmpty, !eventID.isEmpty else { return nil }
        return (calendarID, eventID)
    }

    public static func managedEvent(
        from event: GoogleEvent,
        calendarID: String,
        calendarName: String,
        timeZone: TimeZone = .current
    ) -> ManagedEvent? {
        guard let eventID = event.id,
              let interval = interval(for: event, timeZone: timeZone) else { return nil }
        return ManagedEvent(
            id: managedEventID(calendarID: calendarID, eventID: eventID),
            title: event.summary ?? "(无标题)",
            start: interval.start,
            end: interval.end,
            calendarName: calendarName,
            isAllDay: event.start?.date != nil,
            isRecurring: !(event.recurrence ?? []).isEmpty,
            type: eventType(from: event),
            notes: event.notes
        )
    }

    public static func conflict(
        from event: GoogleEvent,
        calendarName: String,
        timeZone: TimeZone = .current
    ) -> CalendarConflict? {
        guard let eventID = event.id,
              let interval = interval(for: event, timeZone: timeZone) else { return nil }
        return CalendarConflict(
            id: eventID,
            title: event.summary ?? "（无标题事件）",
            start: interval.start,
            end: interval.end,
            calendarName: calendarName,
            isAllDay: event.start?.date != nil
        )
    }

    /// 解析事件区间。全天事件的 `end.date` 是排他日期，与 `EventDraft.calendarInterval` 一致。
    public static func interval(for event: GoogleEvent, timeZone: TimeZone = .current) -> DateInterval? {
        guard let start = event.start, let end = event.end else { return nil }

        if let startDate = start.date {
            guard let startDay = GoogleDateCodec.dateOnly(startDate, timeZone: timeZone) else { return nil }
            let endDay: Date
            if let endDate = end.date, let parsed = GoogleDateCodec.dateOnly(endDate, timeZone: timeZone) {
                endDay = parsed
            } else {
                endDay = startDay.addingTimeInterval(86_400)
            }
            guard endDay > startDay else { return nil }
            return DateInterval(start: startDay, end: endDay)
        }

        guard let startInstant = start.dateTime.flatMap(GoogleDateCodec.dateTime),
              let endInstant = end.dateTime.flatMap(GoogleDateCodec.dateTime),
              endInstant > startInstant else { return nil }
        return DateInterval(start: startInstant, end: endInstant)
    }

    /// `shiftManagedEvents` 的请求体：只改时间，**绝不重建 notes / 标签**。
    public static func shiftedBody(from event: GoogleEvent, by interval: TimeInterval) -> GoogleEvent? {
        guard let current = Self.interval(for: event) else { return nil }
        let newStart = current.start.addingTimeInterval(interval)
        let newEnd = current.end.addingTimeInterval(interval)

        var updated = GoogleEvent()
        if event.start?.date != nil {
            // 全天事件按天平移，保持日期语义
            let timeZone = TimeZone.current
            updated.start = GoogleEventDateTime(date: GoogleDateCodec.dateOnlyString(newStart, timeZone: timeZone))
            updated.end = GoogleEventDateTime(date: GoogleDateCodec.dateOnlyString(newEnd, timeZone: timeZone))
        } else {
            let timeZone = TimeZone(identifier: event.start?.timeZone ?? "") ?? .current
            updated.start = GoogleEventDateTime(
                dateTime: GoogleDateCodec.dateTimeString(newStart, timeZone: timeZone),
                timeZone: timeZone.identifier
            )
            updated.end = GoogleEventDateTime(
                dateTime: GoogleDateCodec.dateTimeString(newEnd, timeZone: timeZone),
                timeZone: timeZone.identifier
            )
        }
        return updated
    }
}

/// Google 的两种时间表示：`yyyy-MM-dd` 与 RFC3339。
enum GoogleDateCodec {
    static func dateOnlyString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func dateOnly(_ string: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    static func dateTimeString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func dateTime(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
