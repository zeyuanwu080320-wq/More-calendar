import Foundation

/// Provider-independent conventions for tagging and naming what this tool wrote.
///
/// Everything here is pure (no EventKit, no AppKit) and therefore testable in a
/// sandbox without calendar permission. It lives outside `TargetProvider` so
/// that any future target — Reminders, Google Calendar — reuses the exact same
/// tagging contract instead of re-implementing it.
public enum ManagedEventMetadata {
    /// Marks an event as created by this tool. Written into `notes`, which is
    /// the only metadata field every Apple target preserves.
    public static let managedTag = "[SchoolEventInbox-Managed]"

    /// Compatibility tag required by the later management-panel specification.
    public static let compatibilityTag = "[Managed by SchoolEventInbox]"

    /// Prefix of the per-type marker, e.g. `[SchoolEventInbox-Type:exam]`.
    public static let typeTagPrefix = "[SchoolEventInbox-Type:"

    public static func isManagedNotes(_ notes: String?) -> Bool {
        guard let notes else { return false }
        return notes.contains(managedTag) || notes.contains(compatibilityTag)
    }

    /// Builds the final notes body for a written event: the user's own text
    /// first, then the provenance sentence, then both tags and the type tag.
    public static func managedNotes(original: String, type: EventType) -> String {
        var parts: [String] = []
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        parts.append("由 More calendar 导入，已经用户确认。")
        if !trimmed.contains(managedTag) { parts.append(managedTag) }
        if !trimmed.contains(compatibilityTag) { parts.append(compatibilityTag) }
        parts.append("\(typeTagPrefix)\(type.rawValue)]")
        return parts.joined(separator: "\n")
    }

    /// Reads the type marker back out of a managed event's notes.
    public static func eventType(fromNotes notes: String?) -> EventType? {
        guard let notes else { return nil }
        for type in EventType.allCases {
            if notes.contains("\(typeTagPrefix)\(type.rawValue)]") {
                return type
            }
        }
        return nil
    }

    // MARK: - Per-type calendars

    /// Prefix of every calendar this app creates. `EKCalendar` has no notes or
    /// metadata field, so the title prefix is the only durable marker available
    /// and it is what `calendarForWriting` matches across launches.
    public static let managedCalendarPrefix = "More Calendar - "

    public static func managedCalendarTitle(for type: EventType,
                                            language: ManagedCalendarLanguage = .chinese) -> String {
        managedCalendarPrefix + type.managedCalendarLabel(for: language)
    }

    /// Every title this app may have given the calendar for `bucket`, in both
    /// languages. Used to adopt a calendar created under the other language
    /// instead of creating a duplicate next to it.
    public static func knownCalendarTitles(for type: EventType) -> [String] {
        let bucket = type.managedCalendarBucket
        return ManagedCalendarLanguage.allCases.map { managedCalendarTitle(for: bucket, language: $0) }
    }

    /// Maps an existing managed calendar title back to its event-type bucket.
    public static func managedCalendarBucket(forTitle title: String) -> EventType? {
        guard title.hasPrefix(managedCalendarPrefix) else { return nil }
        for type in EventType.allCases {
            if knownCalendarTitles(for: type).contains(title) {
                return type.managedCalendarBucket
            }
        }
        return nil
    }

    /// Colour used for the per-type calendar of `type`.
    public static func managedCalendarColorToken(for type: EventType) -> ManagedCalendarColorToken {
        switch type.managedCalendarBucket {
        case .deadline: return .orange
        case .appointment: return .blue
        case .exam: return .red
        case .birthday: return .purple
        case .activity, .other: return .green
        }
    }
}
