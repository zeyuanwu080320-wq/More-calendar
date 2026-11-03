import Foundation

/// The event categories understood by the extractor.
/// The raw values are part of the DeepSeek JSON contract.
public enum EventType: String, Codable, CaseIterable, Sendable {
    case deadline
    case appointment
    case activity
    case exam
    case birthday
    case other

    public var displayName: String {
        switch self {
        case .deadline: return "截止"
        case .appointment: return "预约"
        case .activity: return "活动"
        case .exam: return "考试"
        case .birthday: return "生日"
        case .other: return "其他"
        }
    }

    /// These categories may never be written without an explicit checked confirmation.
    public var requiresConfirmation: Bool {
        switch self {
        case .deadline, .appointment, .exam, .birthday:
            return true
        case .activity, .other:
            return false
        }
    }

    /// SF Symbols and color tokens live in the core model so both the
    /// confirmation card and the managed-events list can share them.
    public var symbolName: String {
        switch self {
        case .deadline: return "clock.badge.exclamationmark.fill"
        case .appointment: return "calendar.badge.clock"
        case .exam: return "graduationcap.fill"
        case .birthday: return "birthday.cake.fill"
        case .activity, .other: return "calendar"
        }
    }

    public var colorToken: String {
        switch self {
        case .deadline: return "orange"
        case .appointment: return "blue"
        case .exam: return "red"
        case .birthday: return "pink"
        case .activity, .other: return "gray"
        }
    }

    /// Bucket used when routing a written event into its own Apple Calendar.
    ///
    /// `activity` and `other` deliberately share one bucket: they would
    /// otherwise need two calendars with the same colour, which is visually
    /// pointless and confusing in the Calendar sidebar.
    public var managedCalendarBucket: EventType {
        switch self {
        case .activity, .other: return .activity
        default: return self
        }
    }

    /// Localized suffix of the per-type calendar title.
    public func managedCalendarLabel(for language: ManagedCalendarLanguage) -> String {
        switch managedCalendarBucket {
        case .deadline: return language == .english ? "Deadline" : "截止"
        case .appointment: return language == .english ? "Appointment" : "预约"
        case .exam: return language == .english ? "Exam" : "考试"
        case .birthday: return language == .english ? "Birthday" : "生日"
        case .activity, .other: return language == .english ? "Activity" : "活动"
        }
    }
}

/// Language used for the titles of the per-type Apple calendars.
///
/// Lives in Core because `CalendarService` must name calendars without knowing
/// about the SwiftUI `LanguageManager`, which lives in the app target.
public enum ManagedCalendarLanguage: String, CaseIterable, Sendable {
    case chinese
    case english
}
