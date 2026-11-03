import Foundation
import SchoolEventInboxCore
import SwiftUI

public enum AppLanguage: String, CaseIterable, Sendable {
    case zh
    case en

    public var locale: Locale {
        Locale(identifier: self == .en ? "en" : "zh-Hans")
    }

    public var shortLabel: String { self == .en ? "中" : "EN" }
}

public final class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()

    @AppStorage("SchoolEventInbox.uiLanguage") private var storedLanguage: String = AppLanguage.zh.rawValue
    @Published public private(set) var language: AppLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: "SchoolEventInbox.uiLanguage") ?? AppLanguage.zh.rawValue
        self.language = AppLanguage(rawValue: raw) ?? .zh
    }

    public var isEnglish: Bool { language == .en }

    public func toggle() {
        let next: AppLanguage = language == .en ? .zh : .en
        storedLanguage = next.rawValue
        language = next
    }
}

/// Small helper for strings that are assembled at runtime (errors, summaries,
/// status values). Static SwiftUI literals are localized through en.lproj.
public enum L10n {
    public static var isEnglish: Bool {
        LanguageManager.shared.language == .en
    }

    public static func t(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }

    public static func typeName(_ type: EventType) -> String {
        switch type {
        case .deadline: return t("截止", "Deadline")
        case .appointment: return t("预约", "Appointment")
        case .activity: return t("活动", "Activity")
        case .exam: return t("考试", "Exam")
        case .birthday: return t("生日", "Birthday")
        case .other: return t("其他", "Other")
        }
    }

    static func eventStatus(_ status: WorkStatus) -> String {
        switch status {
        case .idle: return t("空闲", "Idle")
        case .ocr: return t("本地 OCR 中…", "Local OCR…")
        case .deepSeek: return t("DeepSeek 解析中…", "DeepSeek parsing…")
        }
    }

    /// Translate runtime-generated Chinese messages. It intentionally handles
    /// only system text, never user titles/locations/evidence.
    public static func dynamic(_ text: String) -> String {
        guard isEnglish, !text.isEmpty else { return text }

        let exact: [String: String] = [
            "日历尚未授权": "Calendar access not granted",
            "日历权限被拒绝": "Calendar access denied",
            "日历权限受系统限制": "Calendar access restricted",
            "已获完整日历权限": "Full calendar access granted",
            "仅有写入权限，无法检查冲突": "Write-only access; conflicts cannot be checked",
            "无法读取日历权限状态": "Calendar authorization status unavailable",
            "日历权限被拒绝。写入按钮已禁用，请到系统设置 > 隐私与安全性 > 日历中授权。": "Calendar access denied. Writing is disabled. Allow access in System Settings > Privacy & Security > Calendars.",
            "日历权限受系统限制，无法写入。": "Calendar access is restricted; writing is unavailable.",
            "无法读取日历权限状态，写入按钮已禁用。": "Calendar authorization status is unavailable; writing is disabled.",
            "首次写入时会请求完整日历权限。": "Full calendar access will be requested on the first write.",
            "当前只有“仅写入”日历权限，无法检查时间冲突。请升级为完整访问后再写入。": "Only Write Only access is granted. Full Access is required to check conflicts.",
            "剪贴板里没有可读取的图片": "No readable image in the clipboard",
            "粘贴内容中没有可读取的图片": "The pasted content contains no readable image",
            "拖入的文件不是可读取的图片": "The dropped file is not a readable image",
            "图片无法读取或超过 25MB": "The image cannot be read or exceeds 25 MB",
            "请先粘贴邮件正文、截图，或拖入图片": "Paste an email body or an image first",
            "没有待写入的已确认事件": "No confirmed events to write",
            "未识别到可确认的事件": "No confirmable events found",
            "日志服务不可用": "Log service unavailable",
            "本地日志已清空": "Local logs cleared",
            "本地日志已清空；未删除任何其他文件。": "Local logs cleared; no other files were deleted.",
            "请输入 API Key": "Enter an API key",
            "已保存到 macOS Keychain（当前构建）": "Saved to the macOS Keychain for this build",
            "已从 Keychain 删除": "Deleted from the Keychain",
            "已确认事件会写入默认日历": "Confirmed events will be written to the default calendar",
            "需人工补充": "Needs manual input",
            "补充开始时间": "Add start time",
            "补充结束时间": "Add end time",
            "开始": "Start",
            "结束": "End",
            "地点": "Location",
            "置信度": "Confidence",
            "需人工确认": "Needs confirmation",
            "已写入": "Written",
            "确认写入": "Confirm write",
            "已确认（关键类型锁定）": "Confirmed (critical type locked)",
            "全天": "All-day",
            "结束早于开始": "End is before start",
            "默认与开始同一天": "Same day as start by default",
            "未提供，写入时按开始 +1 小时占位": "Not provided; a 1-hour placeholder is used on write",
            "（模型未提供原文片段，请重点核对）": "No evidence supplied; review carefully",
            "未识别到开始时间，需人工补充。": "No start time found; please add it.",
            "日期无法可靠解析，已置空，需人工补充。": "The date could not be parsed reliably; it was left empty.",
            "结束时间无法可靠解析，已置空。": "The end time could not be parsed; it was left empty.",
            "原始时间未标明时区，已按本机时区解释，请确认。": "The source did not specify a time zone; local time was assumed.",
            "原文只有日期没有具体时间，已设为全天，请确认。": "Only a date was provided; the event was set to all-day.",
            "结束日期早于开始日期，请核对。": "The end date is before the start date.",
            "循环事件不支持批量平移，请单条修改": "Recurring events cannot be batch-shifted. Edit them individually.",
            "该事件不是由本工具创建，已拒绝操作": "This event was not created by this tool.",
            "这将同时从 Apple 日历中移除它们。": "They will also be removed from Apple Calendar.",
            "事件信息不完整，无法写入": "The event is incomplete and cannot be written.",
            "没有可写入的默认日历": "No default calendar is available.",
            "日历事件不存在或已被删除": "The calendar event no longer exists.",
            "Keychain 已保存": "Saved in Keychain",
            "存在但不可读": "Present but unreadable",
            "已配置": "Configured",
            "未配置": "Not configured",
            "标题为空": "Title is empty",
            "尚未确认": "Not confirmed",
            "需补充开始时间": "Start time is required",
            "结束时间必须晚于开始时间": "End time must be after start time",
            "结束日期不能早于开始日期": "End date cannot be before start date",
            // Apple Reminders target (V2.0)
            "提醒事项权限被拒绝。写入按钮已禁用，请到系统设置 > 隐私与安全性 > 提醒事项中授权。": "Reminders access denied. Writing is disabled. Allow access in System Settings > Privacy & Security > Reminders.",
            "提醒事项权限受系统限制，无法写入。": "Reminders access is restricted; writing is unavailable.",
            "无法读取提醒事项权限状态，写入按钮已禁用。": "Reminders authorization status is unavailable; writing is disabled.",
            "首次写入时会请求完整提醒事项权限。": "Full Reminders access will be requested on the first write.",
            "当前只有“仅写入”提醒事项权限。请升级为完整访问后再写入。": "Only Write Only Reminders access is granted. Upgrade to Full Access before writing.",
            "提醒事项权限未授予，未写入任何事件": "Reminders access was not granted; no events were written",
            "请求提醒事项权限失败，未写入任何事件": "Reminders permission request failed; no events were written",
            // Target-neutral wording shared by both providers
            "权限被拒绝，请到系统设置授权": "Access denied. Allow access in System Settings.",
            "没有可写入的默认位置": "No default target is available.",
            "该条目不存在或已被删除": "The item no longer exists.",
            "该条目不是由本工具创建，已拒绝操作": "This item was not created by this tool."
        ]
        if let value = exact[text] { return value }

        let patterns: [(String, String)] = [
            ("解析失败：", "Parse failed: "),
            ("读取 Keychain 失败：", "Keychain read failed: "),
            ("请求日历权限失败：", "Calendar permission request failed: "),
            ("请求日历权限失败，未写入任何事件", "Calendar permission request failed; no events were written"),
            ("日历权限未授予，未写入任何事件", "Calendar access was not granted; no events were written"),
            ("仅获得写入权限，无法检查冲突，未写入任何事件", "Only Write Only access was granted; no events were written"),
            ("写入日历失败：", "Calendar write failed: "),
            ("请求提醒事项权限失败：", "Reminders permission request failed: "),
            ("写入失败：", "Write failed: "),
            ("无法读取图片：", "Cannot read image: "),
            ("清空日志失败：", "Failed to clear logs: "),
            ("导出失败：", "Export failed: "),
            ("已导出 ", "Exported "),
            (" 条到 ", " records to "),
            ("演示数据：", "Demo data: "),
            ("已识别 ", "Recognized "),
            (" 条候选事件，请逐条核对后再写入", " candidate events. Review each before writing."),
            (" 条候选事件", " candidate events"),
            ("已写入 ", "Wrote "),
            (" 条，", " events; "),
            (" 条时间冲突未写入", " skipped due to time conflicts"),
            ("发现 ", "Found "),
            (" 条时间冲突：冲突事件已跳过，可在卡片中选择“冲突仍写入”后再次写入。", " time conflicts. Conflicting events were skipped; enable “Write anyway” to write them."),
            ("已记录一次漏检反馈（不包含原文或敏感字段），可在最近 14 天统计中查看。", "Missed-event feedback recorded (no content or sensitive fields)."),
            ("输入已修改，当前卡片仍基于上一次解析。请重新解析后再写入。", "Input changed. Cards still reflect the previous parse; parse again before writing."),
            ("其中 ", "Of them, "),
            (" 条为循环事件，将删除其未来的所有发生记录。", " recur; all future occurrences will be removed."),
            ("已删除 ", "Deleted "),
            (" 条事件", " events"),
            ("成功平移 ", "Shifted "),
            (" 条因冲突失败", " failed due to conflicts"),
            (" 条失败", " failed"),
            (" 条已选择", " selected"),
            ("循环事件不支持批量平移，请单条修改", "Recurring events cannot be batch-shifted. Edit them individually."),
            ("近 ", "Last "),
            (" 天：使用 ", " days: uses "),
            (" 次 · 修改率 ", ", edit rate "),
            ("% · 漏检反馈 ", "%, missed feedback "),
            (" 次", "")
        ]
        var result = text
        for (needle, replacement) in patterns {
            result = result.replacingOccurrences(of: needle, with: replacement)
        }
        return result

}

}
