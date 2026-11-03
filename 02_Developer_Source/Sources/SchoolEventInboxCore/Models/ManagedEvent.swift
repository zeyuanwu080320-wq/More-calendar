import Foundation

/// Authorization state of a write target.
///
/// Deliberately target-neutral: Apple Calendar and Apple Reminders both use it,
/// and the write button's enabled/disabled logic reads it without knowing which
/// provider is active.
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

/// An event this tool created, as shown in the management panel.
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
