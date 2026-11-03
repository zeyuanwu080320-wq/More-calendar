import AppKit
import EventKit
import Foundation

/// Apple Reminders target, backed by EventKit.
///
/// A reminder is not a time-slot event: it has a due date, no end date and no
/// calendar grid, so it only satisfies `TargetProvider` — never
/// `ManagedEventProvider`. That split is what keeps "conflict detection" and
/// "batch shift" out of this type instead of stubbing them with empty methods.
///
/// Per-type reminders lists reuse exactly the same titles, colours and managed
/// tags as the calendar provider, so `ManagedEventMetadata` stays the single
/// source of truth for naming.
@MainActor
public final class AppleRemindersProvider: TargetProvider {
    private let store = EKEventStore()

    /// List identifiers created/found in this session, keyed by bucket. Same
    /// reason as the calendar provider: `calendars(for:)` may lag behind
    /// `saveCalendar`, so a batch must not create the same list twice.
    private var routedListIDs: [EventType: String] = [:]

    public init() {}

    // MARK: - TargetProvider

    public var providerID: TargetProviderID { .appleReminders }

    public var displayName: String { "Apple 提醒事项" }

    public var authorizationState: CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .fullAccess: return .fullAccess
        case .writeOnly: return .writeOnly
        @unknown default: return .unknown
        }
    }

    public var targetName: String? {
        store.defaultCalendarForNewReminders()?.title
    }

    /// Language for newly created list titles.
    public var titleLanguage: ManagedCalendarLanguage = .chinese

    /// Non-fatal reason the last write fell back to the default list.
    public private(set) var routingNotice: String?

    public func resetRoutingNotice() {
        routingNotice = nil
    }

    @discardableResult
    public func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: TargetProviderError.saveFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Reminders occupy no time slot, so there is nothing to clash with.
    ///
    /// Returning an empty array (instead of throwing) keeps `AppModel`'s write
    /// loop free of target-specific branching: the conflict card simply never
    /// appears for reminders.
    public func findConflicts(for draft: EventDraft) async throws -> [CalendarConflict] {
        []
    }

    public func saveEvents(_ drafts: [EventDraft]) async throws {
        for draft in drafts {
            try save(draft)
        }
    }

    /// Writes exactly one user-confirmed reminder.
    private func save(_ draft: EventDraft) throws {
        guard authorizationState.isGranted else { throw TargetProviderError.accessDenied }
        guard draft.hasStart,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.confirmed else {
            throw TargetProviderError.invalidEvent
        }

        let routed = reminderListForWriting(draft.type)
        guard let targetList = routed ?? store.defaultCalendarForNewReminders() else {
            throw TargetProviderError.noDefaultTarget
        }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = targetList
        reminder.title = draft.title
        reminder.notes = ManagedEventMetadata.managedNotes(original: draft.notes, type: draft.type)
        reminder.dueDateComponents = Self.dueDateComponents(for: draft)
        reminder.isCompleted = false

        // Birthdays repeat yearly, matching the calendar provider so the two
        // targets express the same intent.
        if draft.type == .birthday {
            reminder.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)]
        } else {
            reminder.recurrenceRules = nil
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw TargetProviderError.saveFailed(error.localizedDescription)
        }
    }

    /// The due timestamp for a draft.
    ///
    /// Reminders have a single due point, so the draft's start is used. An
    /// all-day draft (and a birthday) becomes a date-only due date: including a
    /// time component would make the reminder fire at 00:00 instead of "that
    /// day". Pure and nonisolated so the self-test can assert it without
    /// reminder permission.
    public nonisolated static func dueDateComponents(for draft: EventDraft,
                                                     calendar: Calendar = .current) -> DateComponents {
        let interval = draft.calendarInterval(calendar: calendar)
        if draft.allDay || draft.type == .birthday {
            let day = calendar.startOfDay(for: interval.start)
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.timeZone = calendar.timeZone
            return components
        }
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: interval.start)
        components.timeZone = calendar.timeZone
        return components
    }

    /// Renames every managed reminders list to the given language.
    ///
    /// Best-effort like the calendar provider: no access or a failed rename is
    /// silent, and must never block the UI.
    @discardableResult
    public func syncLocalizedTitles(to language: ManagedCalendarLanguage) async -> Int {
        titleLanguage = language
        guard authorizationState.isGranted else { return 0 }
        var renamed = 0
        for list in store.calendars(for: .reminder) {
            guard list.allowsContentModifications, !list.isSubscribed, !list.isImmutable,
                  let bucket = ManagedEventMetadata.managedCalendarBucket(forTitle: list.title) else { continue }
            let target = ManagedEventMetadata.managedCalendarTitle(for: bucket, language: language)
            guard list.title != target else { continue }
            if rename(list, to: target) {
                renamed += 1
                routedListIDs[bucket] = list.calendarIdentifier
            }
        }
        return renamed
    }

    // MARK: - Per-type lists

    /// Returns the managed reminders list for `type`, creating it on first use.
    /// Returns nil when no writable source exists, so the caller falls back to
    /// the user's default list.
    private func reminderListForWriting(_ type: EventType) -> EKCalendar? {
        let bucket = type.managedCalendarBucket
        let title = ManagedEventMetadata.managedCalendarTitle(for: type, language: titleLanguage)
        if let identifier = routedListIDs[bucket],
           let cached = store.calendar(withIdentifier: identifier),
           cached.allowsContentModifications {
            _ = rename(cached, to: title)
            return cached
        }
        for candidate in ManagedEventMetadata.knownCalendarTitles(for: type) {
            if let existing = writableList(titled: candidate) {
                routedListIDs[bucket] = existing.calendarIdentifier
                _ = rename(existing, to: title)
                return existing
            }
        }
        guard let source = listCreationSource() else {
            routingNotice = "找不到可创建提醒事项列表的账户，本次写入已回退到默认列表"
            return nil
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = title
        list.source = source
        list.color = ManagedEventMetadata.managedCalendarColorToken(for: type).nsColor
        do {
            try store.saveCalendar(list, commit: true)
            routedListIDs[bucket] = list.calendarIdentifier
            return list
        } catch {
            routingNotice = "创建提醒事项列表「\(title)」失败（\(error.localizedDescription)），本次写入已回退到默认列表"
            return nil
        }
    }

    private func rename(_ list: EKCalendar, to title: String) -> Bool {
        guard list.title != title, list.allowsContentModifications else {
            return list.title == title
        }
        list.title = title
        do {
            try store.saveCalendar(list, commit: true)
            return true
        } catch {
            return false
        }
    }

    private func writableList(titled title: String) -> EKCalendar? {
        store.calendars(for: .reminder).first { list in
            list.title == title
                && list.allowsContentModifications
                && !list.isSubscribed
                && !list.isImmutable
        }
    }

    /// Prefers the source hosting the default reminders list, then a local
    /// account, then any CalDAV account.
    private func listCreationSource() -> EKSource? {
        if let source = store.defaultCalendarForNewReminders()?.source,
           source.sourceType != .subscribed,
           source.sourceType != .birthdays {
            return source
        }
        let sources = store.sources
        if let local = sources.first(where: { $0.sourceType == .local }) { return local }
        return sources.first(where: { $0.sourceType == .calDAV })
    }
}
