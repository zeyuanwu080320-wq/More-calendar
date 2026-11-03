import AppKit
import EventKit
import Foundation

public enum CalendarAccessState: String, Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case fullAccess
    case writeOnly
    case unknown

    public var canAttemptWrite: Bool {
        switch self {
        case .notDetermined, .fullAccess: return true
        case .writeOnly, .denied, .restricted, .unknown: return false
        }
    }

    public var isGranted: Bool { self == .fullAccess }

    public var displayText: String {
        switch self {
        case .notDetermined: return "日历尚未授权"
        case .denied: return "日历权限被拒绝"
        case .restricted: return "日历权限受系统限制"
        case .fullAccess: return "已获完整日历权限"
        case .writeOnly: return "仅有写入权限，无法检查冲突"
        case .unknown: return "无法读取日历权限状态"
        }
    }
}

public enum CalendarServiceError: LocalizedError, Equatable, Sendable {
    case accessDenied
    case noDefaultCalendar
    case invalidEvent
    case eventNotFound
    case notManagedEvent
    case recurringBatchUnsupported
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied: return "日历权限被拒绝，请到系统设置授权"
        case .noDefaultCalendar: return "没有可写入的默认日历"
        case .invalidEvent: return "事件信息不完整，无法写入"
        case .eventNotFound: return "日历事件不存在或已被删除"
        case .notManagedEvent: return "该事件不是由本工具创建，已拒绝操作"
        case .recurringBatchUnsupported: return "循环事件不支持批量平移，请单条修改"
        case .saveFailed(let reason): return "写入日历失败：\(reason)"
        }
    }
}

public struct ManagedEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarName: String
    public let isAllDay: Bool
    public let isRecurring: Bool
    public let type: EventType?
    public let notes: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        calendarName: String,
        isAllDay: Bool,
        isRecurring: Bool,
        type: EventType?,
        notes: String?
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarName = calendarName
        self.isAllDay = isAllDay
        self.isRecurring = isRecurring
        self.type = type
        self.notes = notes
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct ManagedShiftResult: Equatable, Sendable {
    public let shifted: Int
    public let conflicts: Int
    public let failed: Int
    /// One entry per skipped event, so the UI can name both sides of the clash
    /// instead of only reporting a bare count.
    public let conflictDetails: [ManagedShiftConflict]

    public init(shifted: Int, conflicts: Int, failed: Int, conflictDetails: [ManagedShiftConflict] = []) {
        self.shifted = shifted
        self.conflicts = conflicts
        self.failed = failed
        self.conflictDetails = conflictDetails
    }
}

/// Describes one event that could not be shifted because its new time slot
/// overlaps an existing event.
public struct ManagedShiftConflict: Identifiable, Equatable, Sendable {
    public let id: String
    /// Title of the event the user tried to move.
    public let shiftedTitle: String
    /// Title of the event already occupying that slot.
    public let blockingTitle: String
    public let newStart: Date
    public let blockingStart: Date

    public init(id: String, shiftedTitle: String, blockingTitle: String, newStart: Date, blockingStart: Date) {
        self.id = id
        self.shiftedTitle = shiftedTitle
        self.blockingTitle = blockingTitle
        self.newStart = newStart
        self.blockingStart = blockingStart
    }
}

/// Outcome of deleting a hand-picked set of managed events.
public struct ManagedDeleteResult: Equatable, Sendable {
    public let deleted: Int
    public let failed: Int

    public init(deleted: Int, failed: Int) {
        self.deleted = deleted
        self.failed = failed
    }
}

/// Colour assigned to each per-type calendar.
///
/// EventKit has no `EKCalendarColor` enum (only `EKCalendar.color: NSColor` and
/// `EKCalendar.CGColor`), so the mapping is modelled as a small value type: the
/// pure mapping stays testable, and only `nsColor` touches AppKit.
public enum ManagedCalendarColorToken: String, Equatable, Hashable, Sendable {
    case orange
    case blue
    case red
    case purple
    case green

    public var nsColor: NSColor {
        switch self {
        case .orange: return .systemOrange
        case .blue: return .systemBlue
        case .red: return .systemRed
        case .purple: return .systemPurple
        case .green: return .systemGreen
        }
    }
}

@MainActor
public final class CalendarService {
    // Immutable String constants carry no actor state. They are explicitly
    // nonisolated because `isManagedNotes` / `managedNotes` are nonisolated
    // helpers (and the CLI self-test reads them off the main actor); without
    // this every call site emits a Swift 6 actor-isolation warning.
    public nonisolated static let managedTag = "[SchoolEventInbox-Managed]"
    /// Compatibility tag required by the later management-panel specification.
    public nonisolated static let compatibilityTag = "[Managed by SchoolEventInbox]"
    public nonisolated static let typeTagPrefix = "[SchoolEventInbox-Type:"

    public nonisolated static func isManagedNotes(_ notes: String?) -> Bool {
        guard let notes else { return false }
        return notes.contains(managedTag) || notes.contains(compatibilityTag)
    }

    public nonisolated static func managedNotes(original: String, type: EventType) -> String {
        var parts: [String] = []
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        parts.append("由 More calendar 导入，已经用户确认。")
        if !trimmed.contains(managedTag) { parts.append(managedTag) }
        if !trimmed.contains(compatibilityTag) { parts.append(compatibilityTag) }
        parts.append("\(typeTagPrefix)\(type.rawValue)]")
        return parts.joined(separator: "\n")
    }

    private let store = EKEventStore()

    // MARK: - Per-type calendars

    /// Prefix of every calendar this app creates. `EKCalendar` has no notes or
    /// metadata field, so the title prefix is the only durable marker available
    /// and it is what `calendarForWriting` matches across launches.
    public nonisolated static let managedCalendarPrefix = "More Calendar - "

    public nonisolated static func managedCalendarTitle(for type: EventType,
                                                        language: ManagedCalendarLanguage = .chinese) -> String {
        managedCalendarPrefix + type.managedCalendarLabel(for: language)
    }

    /// Every title this app may have given the calendar for `bucket`, in both
    /// languages. Used to adopt a calendar created under the other language
    /// instead of creating a duplicate next to it.
    public nonisolated static func knownCalendarTitles(for type: EventType) -> [String] {
        let bucket = type.managedCalendarBucket
        return ManagedCalendarLanguage.allCases.map { managedCalendarTitle(for: bucket, language: $0) }
    }

    /// Maps an existing managed calendar title back to its event-type bucket.
    public nonisolated static func managedCalendarBucket(forTitle title: String) -> EventType? {
        guard title.hasPrefix(managedCalendarPrefix) else { return nil }
        for type in EventType.allCases {
            if knownCalendarTitles(for: type).contains(title) {
                return type.managedCalendarBucket
            }
        }
        return nil
    }

    public nonisolated static func managedCalendarColorToken(for type: EventType) -> ManagedCalendarColorToken {
        switch type.managedCalendarBucket {
        case .deadline: return .orange
        case .appointment: return .blue
        case .exam: return .red
        case .birthday: return .purple
        case .activity, .other: return .green
        }
    }

    /// Non-fatal reason the last write fell back to the default calendar.
    public private(set) var routingNotice: String?

    /// Calendar identifiers created/found in this session, keyed by bucket.
    /// `EKEventStore.calendars(for:)` is not guaranteed to list a calendar
    /// immediately after `saveCalendar`, so a batch writing two exams would
    /// otherwise try to create the same calendar twice.
    private var routedCalendarIDs: [EventType: String] = [:]

    public func resetRoutingNotice() {
        routingNotice = nil
    }

    /// Language for newly created calendar titles, and for titles this service
    /// rewrites. The app sets it from `LanguageManager` before writing.
    public var titleLanguage: ManagedCalendarLanguage = .chinese

    /// Returns the managed calendar for `type`, creating it on first use.
    /// Returns nil when no writable source exists or creation fails, so the
    /// caller can fall back to the user's default calendar.
    public func calendarForWriting(_ type: EventType) -> EKCalendar? {
        let bucket = type.managedCalendarBucket
        let title = Self.managedCalendarTitle(for: type, language: titleLanguage)
        if let identifier = routedCalendarIDs[bucket],
           let cached = store.calendar(withIdentifier: identifier),
           cached.allowsContentModifications {
            // The user may have switched language since the cache was filled.
            _ = rename(cached, to: title)
            return cached
        }
        // Prefer the current language, but adopt a calendar created earlier in
        // the other language and rename it rather than creating a duplicate.
        for candidate in Self.knownCalendarTitles(for: type) {
            if let existing = writableCalendar(titled: candidate) {
                routedCalendarIDs[bucket] = existing.calendarIdentifier
                _ = rename(existing, to: title)
                return existing
            }
        }
        guard let source = calendarCreationSource() else {
            routingNotice = "找不到可创建日历的账户，本次写入已回退到默认日历"
            return nil
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title
        calendar.source = source
        calendar.color = Self.managedCalendarColorToken(for: type).nsColor
        do {
            try store.saveCalendar(calendar, commit: true)
            routedCalendarIDs[bucket] = calendar.calendarIdentifier
            return calendar
        } catch {
            routingNotice = "创建日历「\(title)」失败（\(error.localizedDescription)），本次写入已回退到默认日历"
            return nil
        }
    }

    /// Renames every managed calendar to the given language.
    ///
    /// Renaming a calendar needs full calendar access. When access is missing
    /// or a rename fails, this silently does nothing: it must never block the
    /// main flow or surface an error dialog.
    @discardableResult
    public func syncManagedCalendarTitles(to language: ManagedCalendarLanguage) -> Int {
        titleLanguage = language
        guard authorizationState.isGranted else { return 0 }
        var renamed = 0
        for calendar in store.calendars(for: .event) {
            guard calendar.allowsContentModifications, !calendar.isSubscribed, !calendar.isImmutable,
                  let bucket = Self.managedCalendarBucket(forTitle: calendar.title) else { continue }
            let target = Self.managedCalendarTitle(for: bucket, language: language)
            guard calendar.title != target else { continue }
            if rename(calendar, to: target) {
                renamed += 1
                routedCalendarIDs[bucket] = calendar.calendarIdentifier
            }
        }
        return renamed
    }

    /// Saves a new title on an existing calendar. Returns false on any failure.
    private func rename(_ calendar: EKCalendar, to title: String) -> Bool {
        guard calendar.title != title, calendar.allowsContentModifications else {
            return calendar.title == title
        }
        calendar.title = title
        do {
            try store.saveCalendar(calendar, commit: true)
            return true
        } catch {
            return false
        }
    }

    private func writableCalendar(titled title: String) -> EKCalendar? {
        store.calendars(for: .event).first { calendar in
            calendar.title == title
                && calendar.allowsContentModifications
                && !calendar.isSubscribed
                && !calendar.isImmutable
        }
    }

    /// Prefers the account that hosts the user's default calendar (usually
    /// iCloud), then a local account, then any CalDAV account. Subscribed and
    /// birthday sources cannot hold user events, so they are never used.
    private func calendarCreationSource() -> EKSource? {
        if let source = store.defaultCalendarForNewEvents?.source,
           source.sourceType != .subscribed,
           source.sourceType != .birthdays {
            return source
        }
        let sources = store.sources
        if let local = sources.first(where: { $0.sourceType == .local }) { return local }
        return sources.first(where: { $0.sourceType == .calDAV })
    }

    public init() {}

    public var authorizationState: CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .fullAccess: return .fullAccess
        case .writeOnly: return .writeOnly
        @unknown default: return .unknown
        }
    }

    public var defaultCalendarName: String? {
        store.defaultCalendarForNewEvents?.title
    }

    @discardableResult
    public func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: CalendarServiceError.saveFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    public func findConflicts(for draft: EventDraft, calendar: Calendar = .current) throws -> [CalendarConflict] {
        let state = authorizationState
        guard state.isGranted else {
            if state == .notDetermined { return [] }
            throw CalendarServiceError.accessDenied
        }
        guard draft.hasStart else { return [] }
        let interval = draft.calendarInterval(calendar: calendar)
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        let matches = store.events(matching: predicate)

        var results: [CalendarConflict] = []
        var seen = Set<String>()
        for event in matches {
            guard event.status != .canceled,
                  let start = event.startDate,
                  let end = event.endDate else { continue }
            guard ConflictDetector.overlaps(interval, DateInterval(start: start, end: end)) else { continue }
            let identifier = event.eventIdentifier ?? UUID().uuidString
            guard seen.insert(identifier).inserted else { continue }
            results.append(
                CalendarConflict(
                    id: identifier,
                    title: event.title ?? "（无标题事件）",
                    start: start,
                    end: end,
                    calendarName: event.calendar?.title ?? "未知日历",
                    isAllDay: event.isAllDay
                )
            )
        }
        return results.sorted { $0.start < $1.start }
    }

    /// Writes exactly one user-confirmed event. The managed tag is mandatory.
    public func write(_ draft: EventDraft, calendar: Calendar = .current) throws {
        guard authorizationState.isGranted else { throw CalendarServiceError.accessDenied }
        guard draft.hasStart,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.confirmed else {
            throw CalendarServiceError.invalidEvent
        }
        // Route the event into its per-type calendar so Apple Calendar shows a
        // colour per category. Falls back to the user's default calendar when
        // the managed calendar cannot be found or created.
        let routed = calendarForWriting(draft.type)
        guard let targetCalendar = routed ?? store.defaultCalendarForNewEvents else {
            throw CalendarServiceError.noDefaultCalendar
        }

        let isBirthday = draft.type == .birthday
        let interval = draft.calendarInterval(calendar: calendar)
        let birthdayStart = calendar.startOfDay(for: interval.start)
        let birthdayEnd = calendar.date(byAdding: .day, value: 1, to: birthdayStart)
            ?? birthdayStart.addingTimeInterval(86_400)

        let event = EKEvent(eventStore: store)
        event.calendar = targetCalendar
        event.title = draft.title
        event.isAllDay = isBirthday ? true : draft.allDay
        event.startDate = isBirthday ? birthdayStart : interval.start
        event.endDate = isBirthday ? birthdayEnd : interval.end
        event.location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        event.notes = Self.managedNotes(original: draft.notes, type: draft.type)

        if isBirthday {
            event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)]
        } else {
            event.recurrenceRules = nil
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarServiceError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Managed events

    public func fetchManagedEvents(calendar: Calendar = .current, now: Date = Date()) throws -> [ManagedEvent] {
        guard authorizationState.isGranted else { throw CalendarServiceError.accessDenied }
        guard let rangeStart = calendar.date(byAdding: .month, value: -1, to: now),
              let rangeEnd = calendar.date(byAdding: .year, value: 1, to: now) else {
            return []
        }
        let predicate = store.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: nil)
        var seen = Set<String>()
        var results: [ManagedEvent] = []
        for event in store.events(matching: predicate) {
            guard isManaged(event),
                  event.status != .canceled,
                  let start = event.startDate,
                  let end = event.endDate,
                  let identifier = event.eventIdentifier,
                  seen.insert(identifier).inserted else { continue }
            results.append(
                ManagedEvent(
                    id: identifier,
                    title: event.title ?? "(无标题)",
                    start: start,
                    end: end,
                    calendarName: event.calendar?.title ?? "未知日历",
                    isAllDay: event.isAllDay,
                    isRecurring: !(event.recurrenceRules ?? []).isEmpty,
                    type: type(from: event.notes),
                    notes: event.notes
                )
            )
        }
        return results.sorted { $0.start < $1.start }
    }

    @discardableResult
    public func deleteManagedEvent(id: String) throws -> Int {
        guard authorizationState.isGranted else { throw CalendarServiceError.accessDenied }
        guard let event = store.event(withIdentifier: id), isManaged(event) else {
            throw CalendarServiceError.notManagedEvent
        }
        let span: EKSpan = (event.recurrenceRules ?? []).isEmpty ? .thisEvent : .futureEvents
        do {
            try store.remove(event, span: span, commit: true)
            return 1
        } catch {
            throw CalendarServiceError.saveFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func deleteAllManagedEvents(calendar: Calendar = .current) throws -> Int {
        guard authorizationState.isGranted else { throw CalendarServiceError.accessDenied }
        let events = try fetchManagedEvents(calendar: calendar)
        var removed = 0
        for item in events {
            guard let event = store.event(withIdentifier: item.id), isManaged(event) else { continue }
            let span: EKSpan = (event.recurrenceRules ?? []).isEmpty ? .thisEvent : .futureEvents
            do {
                try store.remove(event, span: span, commit: true)
                removed += 1
            } catch {
                // Continue removing the rest; the view reports the partial result.
            }
        }
        return removed
    }

    /// Deletes an explicit set of managed events (the "delete selected" action).
    ///
    /// Unlike `deleteAllManagedEvents`, untouched events are never touched.
    /// Recurring events are removed with `.futureEvents` so deleting a birthday
    /// does not leave future occurrences behind. IDs that no longer exist, or
    /// that are not managed by this app, are counted as failed and skipped.
    @discardableResult
    public func deleteManagedEvents(ids: [String]) throws -> ManagedDeleteResult {
        guard authorizationState.isGranted else { throw CalendarServiceError.accessDenied }
        var deleted = 0
        var failed = 0
        for id in ids {
            guard let event = store.event(withIdentifier: id), isManaged(event) else {
                failed += 1
                continue
            }
            let span: EKSpan = (event.recurrenceRules ?? []).isEmpty ? .thisEvent : .futureEvents
            do {
                try store.remove(event, span: span, commit: true)
                deleted += 1
            } catch {
                failed += 1
            }
        }
        return ManagedDeleteResult(deleted: deleted, failed: failed)
    }

    /// Shifts non-recurring managed events by a fixed time interval.
    /// Recurring events are rejected by the caller/view before this method.
    public func shiftManagedEvents(ids: [String], by interval: TimeInterval, calendar: Calendar = .current) throws -> ManagedShiftResult {
        guard authorizationState.isGranted else { throw CalendarServiceError.accessDenied }
        guard !ids.isEmpty, interval != 0 else { return ManagedShiftResult(shifted: 0, conflicts: 0, failed: 0) }
        let selectedIDs = Set(ids)
        let managed = try fetchManagedEvents(calendar: calendar)
        let managedIDs = Set(managed.map(\.id))
        guard selectedIDs.isSubset(of: managedIDs) else { throw CalendarServiceError.notManagedEvent }

        var shifted = 0
        var conflicts = 0
        var failed = 0
        var conflictDetails: [ManagedShiftConflict] = []

        for id in ids {
            guard let event = store.event(withIdentifier: id), isManaged(event) else {
                failed += 1
                continue
            }
            if !(event.recurrenceRules ?? []).isEmpty {
                throw CalendarServiceError.recurringBatchUnsupported
            }
            guard let oldStart = event.startDate, let oldEnd = event.endDate else {
                failed += 1
                continue
            }

            let newStart: Date
            let newEnd: Date
            if event.isAllDay {
                let days = Int(interval / 86_400)
                guard days != 0 else {
                    failed += 1
                    continue
                }
                newStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: oldStart) ?? oldStart)
                newEnd = calendar.date(byAdding: .day, value: days, to: oldEnd) ?? oldEnd
            } else {
                newStart = oldStart.addingTimeInterval(interval)
                newEnd = oldEnd.addingTimeInterval(interval)
            }

            if let blocker = conflictingEvent(start: newStart, end: newEnd, excluding: selectedIDs) {
                conflicts += 1
                conflictDetails.append(
                    ManagedShiftConflict(
                        id: id,
                        shiftedTitle: event.title ?? "（无标题事件）",
                        blockingTitle: blocker.title ?? "（无标题事件）",
                        newStart: newStart,
                        blockingStart: blocker.startDate ?? newStart
                    )
                )
                continue
            }

            event.startDate = newStart
            event.endDate = newEnd
            // Never rebuild notes here: this preserves both managed tags.
            do {
                try store.save(event, span: .thisEvent, commit: true)
                shifted += 1
            } catch {
                failed += 1
            }
        }
        return ManagedShiftResult(shifted: shifted, conflicts: conflicts, failed: failed, conflictDetails: conflictDetails)
    }

    // MARK: - Helpers

    private func isManaged(_ event: EKEvent) -> Bool {
        Self.isManagedNotes(event.notes)
    }

    private func type(from notes: String?) -> EventType? {
        guard let notes else { return nil }
        for type in EventType.allCases {
            if notes.contains("\(Self.typeTagPrefix)\(type.rawValue)]") {
                return type
            }
        }
        return nil
    }

    /// Returns the first event that would clash with `start..<end`, so callers
    /// can tell the user *which* event blocked the move.
    private func conflictingEvent(start: Date, end: Date, excluding: Set<String>) -> EKEvent? {
        guard end > start else { return nil }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).first { event in
            guard event.status != .canceled,
                  let eventID = event.eventIdentifier,
                  !excluding.contains(eventID),
                  let eventStart = event.startDate,
                  let eventEnd = event.endDate else { return false }
            return ConflictDetector.overlaps(
                DateInterval(start: start, end: end),
                DateInterval(start: eventStart, end: eventEnd)
            )
        }
    }
}
