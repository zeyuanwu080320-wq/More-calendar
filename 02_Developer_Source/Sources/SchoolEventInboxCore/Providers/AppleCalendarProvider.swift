import AppKit
import EventKit
import Foundation

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

/// Apple Calendar target, backed by EventKit.
///
/// This is the same logic V1.0 carried inside `CalendarService`, moved behind
/// the `TargetProvider` / `ManagedEventProvider` protocols. Behaviour is
/// intentionally identical: same per-type calendar routing, same managed tags,
/// same all-day and birthday handling, same conflict and shift rules.
///
/// Every `import EventKit` in the app resolves to this file.
@MainActor
public final class AppleCalendarProvider: ManagedEventProvider {
    private let store = EKEventStore()

    /// Calendar identifiers created/found in this session, keyed by bucket.
    /// `EKEventStore.calendars(for:)` is not guaranteed to list a calendar
    /// immediately after `saveCalendar`, so a batch writing two exams would
    /// otherwise try to create the same calendar twice.
    private var routedCalendarIDs: [EventType: String] = [:]

    public init() {}

    // MARK: - TargetProvider

    public var providerID: TargetProviderID { .appleCalendar }

    public var displayName: String { "Apple 日历" }

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

    public var targetName: String? {
        store.defaultCalendarForNewEvents?.title
    }

    /// Language for newly created calendar titles, and for titles this provider
    /// rewrites. The app sets it from `LanguageManager` before writing.
    public var titleLanguage: ManagedCalendarLanguage = .chinese

    /// Non-fatal reason the last write fell back to the default calendar.
    public private(set) var routingNotice: String?

    public func resetRoutingNotice() {
        routingNotice = nil
    }

    @discardableResult
    public func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: TargetProviderError.saveFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    public func findConflicts(for draft: EventDraft) async throws -> [CalendarConflict] {
        let calendar = Calendar.current
        let state = authorizationState
        guard state.isGranted else {
            if state == .notDetermined { return [] }
            throw TargetProviderError.accessDenied
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

    /// Writes the given user-confirmed drafts. The managed tag is mandatory.
    ///
    /// `AppModel` calls this with one draft at a time so its per-card conflict,
    /// skip and failure accounting stays identical to V1.0; the array signature
    /// is where a batch-capable target can later write everything at once.
    public func saveEvents(_ drafts: [EventDraft]) async throws {
        for draft in drafts {
            try save(draft)
        }
    }

    /// Writes exactly one user-confirmed event.
    private func save(_ draft: EventDraft) throws {
        let calendar = Calendar.current
        guard authorizationState.isGranted else { throw TargetProviderError.accessDenied }
        guard draft.hasStart,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.confirmed else {
            throw TargetProviderError.invalidEvent
        }
        // Route the event into its per-type calendar so Apple Calendar shows a
        // colour per category. Falls back to the user's default calendar when
        // the managed calendar cannot be found or created.
        let routed = calendarForWriting(draft.type)
        guard let targetCalendar = routed ?? store.defaultCalendarForNewEvents else {
            throw TargetProviderError.noDefaultTarget
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

        event.notes = ManagedEventMetadata.managedNotes(original: draft.notes, type: draft.type)

        if isBirthday {
            event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)]
        } else {
            event.recurrenceRules = nil
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw TargetProviderError.saveFailed(error.localizedDescription)
        }
    }

    /// Renames every managed calendar to the given language.
    ///
    /// Renaming a calendar needs full calendar access. When access is missing
    /// or a rename fails, this silently does nothing: it must never block the
    /// main flow or surface an error dialog.
    @discardableResult
    public func syncLocalizedTitles(to language: ManagedCalendarLanguage) async -> Int {
        titleLanguage = language
        guard authorizationState.isGranted else { return 0 }
        var renamed = 0
        for calendar in store.calendars(for: .event) {
            guard calendar.allowsContentModifications, !calendar.isSubscribed, !calendar.isImmutable,
                  let bucket = ManagedEventMetadata.managedCalendarBucket(forTitle: calendar.title) else { continue }
            let target = ManagedEventMetadata.managedCalendarTitle(for: bucket, language: language)
            guard calendar.title != target else { continue }
            if rename(calendar, to: target) {
                renamed += 1
                routedCalendarIDs[bucket] = calendar.calendarIdentifier
            }
        }
        return renamed
    }

    // MARK: - Per-type calendars

    /// Returns the managed calendar for `type`, creating it on first use.
    /// Returns nil when no writable source exists or creation fails, so the
    /// caller can fall back to the user's default calendar.
    private func calendarForWriting(_ type: EventType) -> EKCalendar? {
        let bucket = type.managedCalendarBucket
        let title = ManagedEventMetadata.managedCalendarTitle(for: type, language: titleLanguage)
        if let identifier = routedCalendarIDs[bucket],
           let cached = store.calendar(withIdentifier: identifier),
           cached.allowsContentModifications {
            // The user may have switched language since the cache was filled.
            _ = rename(cached, to: title)
            return cached
        }
        // Prefer the current language, but adopt a calendar created earlier in
        // the other language and rename it rather than creating a duplicate.
        for candidate in ManagedEventMetadata.knownCalendarTitles(for: type) {
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
        calendar.color = ManagedEventMetadata.managedCalendarColorToken(for: type).nsColor
        do {
            try store.saveCalendar(calendar, commit: true)
            routedCalendarIDs[bucket] = calendar.calendarIdentifier
            return calendar
        } catch {
            routingNotice = "创建日历「\(title)」失败（\(error.localizedDescription)），本次写入已回退到默认日历"
            return nil
        }
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

    // MARK: - Managed events

    public func fetchManagedEvents() async throws -> [ManagedEvent] {
        let calendar = Calendar.current
        let now = Date()
        guard authorizationState.isGranted else { throw TargetProviderError.accessDenied }
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
                    type: ManagedEventMetadata.eventType(fromNotes: event.notes),
                    notes: event.notes
                )
            )
        }
        return results.sorted { $0.start < $1.start }
    }

    @discardableResult
    public func deleteManagedEvent(id: String) async throws -> Int {
        guard authorizationState.isGranted else { throw TargetProviderError.accessDenied }
        guard let event = store.event(withIdentifier: id), isManaged(event) else {
            throw TargetProviderError.notManagedEvent
        }
        let span: EKSpan = (event.recurrenceRules ?? []).isEmpty ? .thisEvent : .futureEvents
        do {
            try store.remove(event, span: span, commit: true)
            return 1
        } catch {
            throw TargetProviderError.saveFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func deleteAllManagedEvents() async throws -> Int {
        guard authorizationState.isGranted else { throw TargetProviderError.accessDenied }
        let events = try await fetchManagedEvents()
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
    public func deleteManagedEvents(ids: [String]) async throws -> ManagedDeleteResult {
        guard authorizationState.isGranted else { throw TargetProviderError.accessDenied }
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
    public func shiftManagedEvents(ids: [String], by interval: TimeInterval) async throws -> ManagedShiftResult {
        let calendar = Calendar.current
        guard authorizationState.isGranted else { throw TargetProviderError.accessDenied }
        guard !ids.isEmpty, interval != 0 else { return ManagedShiftResult(shifted: 0, conflicts: 0, failed: 0) }
        let selectedIDs = Set(ids)
        let managed = try await fetchManagedEvents()
        let managedIDs = Set(managed.map(\.id))
        guard selectedIDs.isSubset(of: managedIDs) else { throw TargetProviderError.notManagedEvent }

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
                throw TargetProviderError.recurringBatchUnsupported
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
        ManagedEventMetadata.isManagedNotes(event.notes)
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
