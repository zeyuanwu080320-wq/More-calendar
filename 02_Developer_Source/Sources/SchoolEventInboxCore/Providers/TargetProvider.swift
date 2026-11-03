import Foundation

/// Stable identifier for a destination the app can write events to.
///
/// V2 will grow Apple Reminders, Google Calendar and To-Do style targets; the
/// identifier lets call sites and (later) settings persist a choice without
/// switching on concrete provider types.
public struct TargetProviderID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The only implementation shipped in this refactor.
    public static let appleCalendar = TargetProviderID(rawValue: "apple.calendar")
    /// Reserved: Apple Reminders target.
    public static let appleReminders = TargetProviderID(rawValue: "apple.reminders")
    /// Reserved: Google Calendar target.
    public static let googleCalendar = TargetProviderID(rawValue: "google.calendar")
}

/// Errors any target can raise while writing.
///
/// The cases are target-neutral because two targets now share them. Messages
/// that used to name "日历" are worded generically so a reminder failure never
/// talks about calendars; the target-specific permission prompts live in
/// `AppModel`, which knows which target is active.
public enum TargetProviderError: LocalizedError, Equatable, Sendable {
    case accessDenied
    case noDefaultTarget
    case invalidEvent
    case eventNotFound
    case notManagedEvent
    case recurringBatchUnsupported
    case saveFailed(String)

    /// 是否属于「需要重新授权」类错误，供调用方决定要不要刷新授权状态。
    public var isAuthorizationFailure: Bool {
        switch self {
        case .accessDenied, .authorizationRequired: return true
        default: return false
        }
    }
    /// 远程目标不可用（网络、令牌、配置）。与「权限被拒绝」区分开。
    case providerUnavailable(String)
    /// 尚未连接或授权已失效（远程目标专用）。**与本地系统权限无关**，
    /// 文案里不能出现「系统设置」，否则会把人引到错误的排查方向。
    case authorizationRequired(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied: return "权限被拒绝，请到系统设置授权"
        case .noDefaultTarget: return "没有可写入的默认位置"
        case .invalidEvent: return "事件信息不完整，无法写入"
        case .eventNotFound: return "该条目不存在或已被删除"
        case .notManagedEvent: return "该条目不是由本工具创建，已拒绝操作"
        case .recurringBatchUnsupported: return "循环事件不支持批量平移，请单条修改"
        case .saveFailed(let reason): return "写入失败：\(reason)"
        case .providerUnavailable(let reason): return "目标暂不可用：\(reason)"
        case .authorizationRequired(let reason): return "需要重新连接：\(reason)"
        }
    }
}

/// A destination that can receive confirmed event drafts.
///
/// This is the seam that replaces V1.0's direct dependency on the
/// EventKit-backed `CalendarService`. Call sites (`AppModel`) depend on this
/// protocol only, so adding a provider never touches the parse pipeline, the
/// confirmation cards, or the window chrome.
///
/// The protocol is main-actor bound on purpose: V1.0 called EventKit
/// synchronously from the main actor, and keeping that shape is what makes this
/// refactor behaviour-preserving. A provider that must hop to another queue can
/// still do so internally.
@MainActor
public protocol TargetProvider: AnyObject {
    /// Stable identifier, used to persist and compare choices.
    var providerID: TargetProviderID { get }

    /// Human-readable name of the target family (e.g. "Apple 日历").
    var displayName: String { get }

    /// Current authorization for this target. Drives the write button state.
    var authorizationState: CalendarAccessState { get }

    /// Name of the concrete container events land in (e.g. the default
    /// calendar title). Shown in the footer bar.
    var targetName: String? { get }

    /// Language for newly created / renamed buckets owned by this target.
    var titleLanguage: ManagedCalendarLanguage { get set }

    /// Non-fatal reason the last write fell back to a less specific container.
    var routingNotice: String? { get }

    /// Clears `routingNotice` before a new batch starts.
    func resetRoutingNotice()

    /// Asks the system for the access this target needs. Returns whether the
    /// user granted it.
    @discardableResult
    func requestAccess() async throws -> Bool

    /// Existing events overlapping the draft's interval. Used to warn on the
    /// confirmation card before writing.
    func findConflicts(for draft: EventDraft) async throws -> [CalendarConflict]

    /// Writes the given drafts.
    ///
    /// The array signature is the batch seam for targets that support batch
    /// writes (e.g. Google Calendar). `AppModel` currently passes a single
    /// draft per call so that its per-card conflict/skip/failure reporting
    /// stays byte-identical to V1.0.
    func saveEvents(_ drafts: [EventDraft]) async throws

    /// Renames containers owned by this target into `language`. Must be
    /// best-effort: never throws, never blocks the UI.
    @discardableResult
    func syncLocalizedTitles(to language: ManagedCalendarLanguage) async -> Int
}

/// A target that can also enumerate, delete and shift the events it created.
///
/// Split out from `TargetProvider` because "manage what this tool wrote" is a
/// capability, not a given: a To-Do style target may never expose a list.
/// `ManagedEventsView` depends on this narrower protocol.
@MainActor
public protocol ManagedEventProvider: TargetProvider {
    /// Events carrying this tool's managed tag, ordered by start date.
    func fetchManagedEvents() async throws -> [ManagedEvent]

    /// Deletes one managed event. Returns the number removed (0 or 1).
    @discardableResult
    func deleteManagedEvent(id: String) async throws -> Int

    /// Deletes exactly the requested set; never touches unselected events.
    func deleteManagedEvents(ids: [String]) async throws -> ManagedDeleteResult

    /// Deletes every managed event. Returns how many were removed.
    @discardableResult
    func deleteAllManagedEvents() async throws -> Int

    /// Shifts non-recurring managed events by a fixed interval.
    func shiftManagedEvents(ids: [String], by interval: TimeInterval) async throws -> ManagedShiftResult
}
