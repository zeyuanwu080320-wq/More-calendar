import AppKit
import Foundation
import SchoolEventInboxCore
import SwiftUI
import UniformTypeIdentifiers

enum WorkStatus: Equatable {
    case idle
    case ocr
    case deepSeek

    var text: String {
        switch self {
        case .idle: return L10n.eventStatus(.idle)
        case .ocr: return L10n.eventStatus(.ocr)
        case .deepSeek: return L10n.eventStatus(.deepSeek)
        }
    }
}

/// Where confirmed drafts are written.
///
/// Lives in the app target because it is a UI choice, not a model concept: the
/// providers themselves only know their own `TargetProviderID`.
enum WriteTarget: String, CaseIterable, Identifiable, Sendable {
    case calendar
    case reminders
    case googleCalendar

    var id: String { rawValue }

    /// Compact label for the segmented picker in the footer.
    var shortTitle: String {
        switch self {
        case .calendar: return L10n.t("日历", "Calendar")
        case .reminders: return L10n.t("提醒事项", "Reminders")
        case .googleCalendar: return L10n.t("Google", "Google")
        }
    }

    var providerID: TargetProviderID {
        switch self {
        case .calendar: return .appleCalendar
        case .reminders: return .appleReminders
        case .googleCalendar: return .googleCalendar
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var emailText: String = ""
    @Published var images: [ImageAttachment] = []
    @Published var drafts: [EventDraft] = []
    @Published var workStatus: WorkStatus = .idle
    @Published var isParsing = false
    @Published var isWriting = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var imageMessage: String?
    @Published var lastWriteSummary: String = ""
    @Published var lastWriteDetail: String = ""
    @Published var calendarState: CalendarAccessState = .unknown
    @Published var calendarName: String = ""
    @Published var apiKeyConfigured = false
    @Published var apiKeyPresence: APIKeyPresence = .missing
    @Published var showAPIKeySheet = false
    @Published var showManagedEvents = false
    @Published var apiKeyDraft = ""
    @Published var apiKeyMessage: String?
    @Published var apiKeyIsError = false
    @Published var logStats: LogStats = .empty
    @Published var logPath: String = ""
    @Published var exportMessage: String?
    @Published var showClearLogConfirmation = false
    @Published var parseSucceeded = false
    @Published var missedFeedbackSent = false
    @Published var isDropTargeted = false

    private let ocrService: OCRService
    private let deepSeek: DeepSeekClient
    private let keychain: APIKeyStore
    private let calendarTarget = AppleCalendarProvider()
    private let remindersTarget = AppleRemindersProvider()
    private let googleTarget = GoogleCalendarProvider()
    private let logService: LogService?

    /// Where the write button sends confirmed drafts. Switching only swaps the
    /// resolved provider; drafts, parsed results and the UI stay untouched.
    @Published private(set) var writeTarget: WriteTarget = .calendar

    /// Which input source the left pane is showing. `email` keeps the V1.0
    /// pipeline (body + screenshot OCR); `text` never touches OCR.
    @Published private(set) var inputSource: InputSource = .email

    /// Free-form text buffer. Deliberately separate from `emailText` so
    /// switching sources never destroys what the user typed.
    @Published var plainText: String = ""

    /// Google 可选日历列表（仅在切到 Google 目标时加载）。
    @Published var googleCalendars: [GoogleCalendarListEntry] = []
    @Published var selectedGoogleCalendarID: String = ""
    @Published var selectedGoogleCalendarName: String = ""

    /// Persisted across launches, following the same pattern as
    /// `LanguageManager`: the wrapper owns the `UserDefaults` write, while the
    /// `@Published` mirrors above are what drive SwiftUI.
    @AppStorage("SchoolEventInbox.writeTarget") private var storedWriteTarget: String = WriteTarget.calendar.rawValue
    @AppStorage("SchoolEventInbox.inputSource") private var storedInputSource: String = InputSource.email.rawValue

    /// The provider for the currently selected write target. Every write, read
    /// and permission call in this class goes through it, never through a
    /// concrete provider type.
    private var target: any TargetProvider {
        switch writeTarget {
        case .calendar: return calendarTarget
        case .reminders: return remindersTarget
        case .googleCalendar: return googleTarget
        }
    }

    private var parseStartedAt: Date?
    private var inputTypeForParse: String = "text"
    private var imageCountForParse = 0
    private var parsedInputSnapshot: String?
    private var parseTask: Task<Void, Never>?
    private var pasteMonitor: Any?

    init(
        ocrService: OCRService = OCRService(),
        deepSeek: DeepSeekClient = DeepSeekService(),
        keychain: APIKeyStore = KeychainService(),
        logService: LogService? = try? LogService()
    ) {
        self.ocrService = ocrService
        self.deepSeek = deepSeek
        self.keychain = keychain
        self.logService = logService
        // Restore the previous session's choices before reading any permission
        // state, so the footer and the write button describe the target the
        // user actually left selected.
        self.writeTarget = WriteTarget(rawValue: storedWriteTarget) ?? .calendar
        self.inputSource = InputSource(rawValue: storedInputSource) ?? .email
        let language: ManagedCalendarLanguage = LanguageManager.shared.isEnglish ? .english : .chinese
        calendarTarget.titleLanguage = language
        remindersTarget.titleLanguage = language
        self.calendarState = target.authorizationState
        self.calendarName = target.targetName ?? ""
        self.logPath = logService?.path ?? ""
        refreshAPIKeyStatus()
        refreshStats()

        // Cmd+V with an image on the pasteboard works anywhere in the window,
        // not only when the small drop zone happens to have keyboard focus.
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "v" else {
                return event
            }
            guard let self else { return event }

            // Let an active text editor handle Cmd+V normally (text paste),
            // even if the pasteboard also carries an image representation.
            if NSApp.keyWindow?.firstResponder is NSTextView {
                return event
            }

            let pasteboard = NSPasteboard.general
            let hasImage = pasteboard.availableType(from: [
                .png,
                .tiff,
                NSPasteboard.PasteboardType("public.jpeg")
            ]) != nil
            guard hasImage else { return event }
            Task { @MainActor [weak self] in
                self?.pasteImageFromClipboard()
            }
            return nil
        }
    }

    deinit {
        if let pasteMonitor {
            NSEvent.removeMonitor(pasteMonitor)
        }
    }

    /// The active target, narrowed to the management capabilities when it
    /// supports them. Reminders deliberately exposes none — a reminder has no
    /// time slot to shift — so the panel is unavailable there instead of
    /// showing something misleading.
    var managedEventProvider: (any ManagedEventProvider)? {
        target as? any ManagedEventProvider
    }

    /// Switches the write target and re-reads its permission state, so the
    /// footer prompt and the write button always describe the active target.
    func selectTarget(_ newTarget: WriteTarget) {
        guard newTarget != writeTarget else { return }
        writeTarget = newTarget
        storedWriteTarget = newTarget.rawValue
        lastWriteSummary = ""
        lastWriteDetail = ""
        errorMessage = nil
        notice = nil
        refreshCalendarStatus()
        if newTarget == .googleCalendar {
            Task {
                await googleTarget.refreshAuthorizationState()
                await googleTarget.loadSelectedCalendarIfNeeded()
                refreshCalendarStatus()
                await refreshGoogleCalendars()
            }
        }
    }

    /// 拉取可写的 Google 日历列表，并恢复上次选择（没有就用 primary）。
    func refreshGoogleCalendars() async {
        do {
            googleCalendars = try await googleTarget.listCalendars()
            let stored = UserDefaults.standard.string(forKey: GoogleCalendarProvider.selectedCalendarDefaultsKey) ?? ""
            let match = googleCalendars.first { $0.id == stored }
                ?? googleCalendars.first { $0.primary == true }
                ?? googleCalendars.first
            if let match {
                selectedGoogleCalendarID = match.id
                selectedGoogleCalendarName = match.summary
            }
        } catch {
            googleCalendars = []
            errorMessage = shortError(error)
        }
    }

    func selectGoogleCalendar(_ entry: GoogleCalendarListEntry) {
        googleTarget.selectCalendar(entry)
        selectedGoogleCalendarID = entry.id
        selectedGoogleCalendarName = entry.summary
        refreshCalendarStatus()
    }

    /// Title of the primary write action, following the selected target.
    var writeActionTitle: String {
        switch writeTarget {
        case .calendar: return L10n.t("写入 Apple 日历", "Write to Apple Calendar")
        case .reminders: return L10n.t("写入 Apple 提醒事项", "Write to Apple Reminders")
        case .googleCalendar: return L10n.t("写入 Google 日历", "Write to Google Calendar")
        }
    }

    var writeActionSymbol: String {
        switch writeTarget {
        case .calendar: return "calendar.badge.plus"
        case .reminders: return "checklist"
        case .googleCalendar: return "globe"
        }
    }

    /// One-line explanation of where confirmed events land.
    var writeTargetHint: String {
        switch writeTarget {
        case .calendar:
            return L10n.t("已确认事件会按类型写入独立日历，失败时回退到默认日历",
                          "Confirmed events go to per-type calendars; falls back to the default calendar")
        case .reminders:
            return L10n.t("已确认事件会按类型写入独立提醒事项列表，到期时间取开始时间，失败时回退到默认列表",
                          "Confirmed events go to per-type reminder lists, due at the start time; falls back to the default list")
        case .googleCalendar:
            return L10n.t("已确认事件会写入你选择的 Google 日历，并按类型着色",
                          "Confirmed events go to the Google calendar you picked, colour-coded by type")
        }
    }

    /// Keeps the per-type calendar titles in the current UI language.
    ///
    /// Renaming a calendar needs full calendar access; providers skip silently
    /// when access is missing, so this never blocks the UI.
    @discardableResult
    func syncCalendarLanguage() async -> Int {
        let language: ManagedCalendarLanguage = LanguageManager.shared.isEnglish ? .english : .chinese
        calendarTarget.titleLanguage = language
        remindersTarget.titleLanguage = language
        let calendarRenamed = await calendarTarget.syncLocalizedTitles(to: language)
        let remindersRenamed = await remindersTarget.syncLocalizedTitles(to: language)
        return calendarRenamed + remindersRenamed
    }

    var hasInput: Bool {
        InputComposer.hasInput(
            source: inputSource,
            emailBody: emailText,
            plainText: plainText,
            imageCount: images.count
        )
    }

    /// Value recorded in the privacy log. "text" is the one value V2.0 adds.
    var currentInputType: String {
        InputComposer.logInputType(
            source: inputSource,
            emailBody: emailText,
            imageCount: images.count
        )
    }

    var unresolvedConflictCount: Int {
        drafts.filter { !$0.isWritten && !$0.conflicts.isEmpty && !$0.writeAnyway }.count
    }

    var writableDraftCount: Int {
        drafts.filter { $0.confirmed && !$0.isWritten }.count
    }

    var hasCriticalUnconfirmed: Bool {
        drafts.contains { $0.isCritical && !$0.confirmed && !$0.isWritten }
    }

    var canTapWrite: Bool {
        guard !isWriting, !isParsing else { return false }
        guard calendarState.canAttemptWrite else { return false }
        return writableDraftCount > 0
    }

    var calendarPermissionPrompt: String? {
        switch (writeTarget, calendarState) {
        case (_, .fullAccess):
            return nil
        case (.googleCalendar, .notDetermined):
            return "尚未连接 Google 账户。点击「连接 Google」授权后即可写入。"
        case (.googleCalendar, .denied), (.googleCalendar, .restricted):
            return "Google 授权已被撤销或受限，请重新连接账户。"
        case (.googleCalendar, .writeOnly):
            return "Google 授权不完整，请重新连接账户。"
        case (.googleCalendar, .unknown):
            return "无法读取 Google 授权状态，写入按钮已禁用。"
        case (.calendar, .denied):
            return "日历权限被拒绝。写入按钮已禁用，请到系统设置 > 隐私与安全性 > 日历中授权。"
        case (.calendar, .restricted):
            return "日历权限受系统限制，无法写入。"
        case (.calendar, .unknown):
            return "无法读取日历权限状态，写入按钮已禁用。"
        case (.calendar, .notDetermined):
            return "首次写入时会请求完整日历权限。"
        case (.calendar, .writeOnly):
            return "当前只有“仅写入”日历权限，无法检查时间冲突。请升级为完整访问后再写入。"
        case (.reminders, .denied):
            return "提醒事项权限被拒绝。写入按钮已禁用，请到系统设置 > 隐私与安全性 > 提醒事项中授权。"
        case (.reminders, .restricted):
            return "提醒事项权限受系统限制，无法写入。"
        case (.reminders, .unknown):
            return "无法读取提醒事项权限状态，写入按钮已禁用。"
        case (.reminders, .notDetermined):
            return "首次写入时会请求完整提醒事项权限。"
        case (.reminders, .writeOnly):
            return "当前只有“仅写入”提醒事项权限。请升级为完整访问后再写入。"
        }
    }

    /// 页脚授权按钮的标题（三种目标文案不同）。
    var authorizeButtonTitle: String {
        switch (writeTarget, calendarState) {
        case (.googleCalendar, _):
            return L10n.t("连接 Google", "Connect Google")
        case (_, .writeOnly):
            return L10n.t("升级为完整访问", "Upgrade to Full Access")
        default:
            return L10n.t("立即授权", "Authorize now")
        }
    }

    func refreshCalendarStatus() {
        calendarState = target.authorizationState
        calendarName = target.targetName ?? ""
    }

    func requestCalendarAccess() {
        guard calendarState == .notDetermined || calendarState == .writeOnly else { return }
        Task {
            do {
                _ = try await target.requestAccess()
            } catch {
                switch writeTarget {
                case .calendar:
                    errorMessage = "请求日历权限失败：\(shortError(error))"
                case .reminders:
                    errorMessage = "请求提醒事项权限失败：\(shortError(error))"
                case .googleCalendar:
                    errorMessage = "连接 Google 账户失败：\(shortError(error))"
                }
            }
            refreshCalendarStatus()
            if writeTarget == .googleCalendar {
                await refreshGoogleCalendars()
            }
        }
    }

    func openCalendarPrivacySettings() {
        let pane = writeTarget == .calendar ? "Privacy_Calendars" : "Privacy_Reminders"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Image input

    func pasteImageFromClipboard() {
        guard let data = ImageSupport.readPasteboardImage() else {
            imageMessage = "剪贴板里没有可读取的图片"
            return
        }
        addImage(data: data, name: "剪贴板截图")
    }

    func handlePasteProviders(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        Task {
            var added = 0
            for provider in providers {
                if let data = await ImageSupport.loadImageData(from: provider) {
                    await MainActor.run {
                        addImage(data: data, name: "粘贴图片")
                    }
                    added += 1
                }
            }
            if added == 0 {
                imageMessage = "粘贴内容中没有可读取的图片"
            }
        }
    }

    func addImageFiles(_ urls: [URL]) {
        var added = 0
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "heic", "tiff"].contains(ext) else { continue }
            guard let data = ImageSupport.imageData(from: url) else {
                imageMessage = "无法读取图片：\(url.lastPathComponent)"
                continue
            }
            addImage(data: data, name: url.lastPathComponent)
            added += 1
        }
        if added == 0 && imageMessage == nil {
            imageMessage = "拖入的文件不是可读取的图片"
        }
    }

    func addImage(data: Data, name: String) {
        guard let png = ImageSupport.normalizedPNG(from: data) else {
            imageMessage = "图片无法读取或超过 25MB"
            return
        }
        images.append(ImageAttachment(data: png, name: name))
        imageMessage = nil
        resetParsedResults()
    }

    func removeImage(id: UUID) {
        images.removeAll { $0.id == id }
        resetParsedResults()
    }

    func clearImages() {
        images.removeAll()
        resetParsedResults()
    }

    func resetParsedResults() {
        drafts = []
        errorMessage = nil
        notice = nil
        lastWriteSummary = ""
        lastWriteDetail = ""
        parseSucceeded = false
        missedFeedbackSent = false
    }

    func inputDidChange() {
        guard parseSucceeded, !isParsing else { return }
        guard currentInputSnapshot() != parsedInputSnapshot else { return }
        notice = "输入已修改，当前卡片仍基于上一次解析。请重新解析后再写入。"
    }

    /// Switches the input source. Parsed cards are kept (same policy as editing
    /// text) and a re-parse hint is raised instead of discarding results.
    func selectInputSource(_ newSource: InputSource) {
        guard newSource != inputSource else { return }
        inputSource = newSource
        storedInputSource = newSource.rawValue
        errorMessage = nil
        inputDidChange()
    }

    /// Identifies "what was parsed", including which source it came from, so
    /// switching sources cannot masquerade as an unchanged input.
    private func currentInputSnapshot() -> String {
        "\(inputSource.rawValue)|\(inputSource == .email ? emailText : plainText)"
    }

    #if DEBUG
    /// Test-only hook used to render the confirmation UI without a network key.
    /// Never triggered unless the app is launched with --demo.
    func loadDemoIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--demo"), drafts.isEmpty else { return }
        emailText = """
        发件人: 教务处
        主题: 2026 春季创新项目报名通知
        报名截止 3月5日；活动 3月8日 14:00；地点 A101。
        """
        let events = [
            ParsedEvent(
                type: .deadline, title: "春季创新项目报名截止",
                start: "2026-03-05T00:00:00+08:00", end: nil, allDay: true,
                location: nil, confidence: 0.96, evidence: "报名截止 3月5日",
                needsConfirmation: true, notes: ""
            ),
            ParsedEvent(
                type: .activity, title: "春季创新项目说明会",
                start: "2026-03-08T14:00:00+08:00", end: nil, allDay: false,
                location: "A101", confidence: 0.93,
                evidence: "活动 3月8日 14:00；地点 A101",
                needsConfirmation: true, notes: ""
            ),
            ParsedEvent(
                type: .appointment, title: "校医院体检预约",
                start: "2026-03-12T09:30:00+08:00", end: nil, allDay: false,
                location: "校医院三楼 305", confidence: 0.88,
                evidence: "预约时间：2026年3月12日 09:30；地点：校医院三楼 305",
                needsConfirmation: true, notes: "请提前 10 分钟到达"
            )
            ,ParsedEvent(
                type: .birthday, title: "朋友生日",
                start: "2026-03-20T00:00:00+08:00", end: nil, allDay: true,
                location: nil, confidence: 0.9,
                evidence: "3月20日生日",
                needsConfirmation: true, notes: "每年重复"
            )
        ]
        drafts = DraftFactory.makeDrafts(from: events)
        parseSucceeded = true
        parsedInputSnapshot = currentInputSnapshot()
        notice = "演示数据：4 条候选事件，请逐条核对后再写入"
        drafts[1].conflicts = [
            CalendarConflict(
                id: "demo-conflict",
                title: "已有课程",
                start: Calendar.current.date(byAdding: .minute, value: 15, to: drafts[1].start) ?? drafts[1].start,
                end: Calendar.current.date(byAdding: .minute, value: 45, to: drafts[1].start) ?? drafts[1].start,
                calendarName: "默认日历",
                isAllDay: false
            )
        ]
    }
    #endif

    // MARK: - Parse

    func parse() {
        guard !isParsing else { return }
        guard hasInput else {
            errorMessage = inputSource == .email
                ? "请先粘贴邮件正文、截图，或拖入图片"
                : "请先输入要解析的文本"
            return
        }
        parseTask?.cancel()
        resetParsedResults()
        isParsing = true
        parseStartedAt = Date()
        inputTypeForParse = currentInputType
        imageCountForParse = inputSource == .email ? images.count : 0
        // The text source never enters the OCR state: no images are consulted.
        workStatus = (inputSource == .email && !images.isEmpty) ? .ocr : .deepSeek

        parseTask = Task { [weak self] in
            await self?.performParse()
        }
    }

    private func performParse() async {
        defer {
            isParsing = false
            workStatus = .idle
            parseTask = nil
        }

        // OCR is scoped to the email source. In text mode `images` is never
        // read at all, so "skip OCR" holds even if screenshots from the email
        // tab are still buffered in memory.
        var ocrSections: [InputComposer.OCRSection] = []
        if inputSource == .email && !images.isEmpty {
            workStatus = .ocr
            for (index, image) in images.enumerated() {
                do {
                    let result = try await ocrService.recognize(imageData: image.data)
                    ocrSections.append(InputComposer.OCRSection(name: image.name, text: result.text))
                } catch {
                    failParse(
                        message: "第 \(index + 1) 张图片 OCR 失败：\(shortError(error))",
                        logError: "ocr_failed"
                    )
                    return
                }
            }
        }

        workStatus = .deepSeek
        let apiKey: String
        do {
            guard let stored = try keychain.readAPIKey(), !stored.isEmpty else {
                failParse(message: "未配置 DeepSeek API Key，请点击右上角“API Key”设置", logError: "missing_api_key")
                return
            }
            apiKey = stored
            UserDefaults.standard.set(true, forKey: Self.apiKeyPresenceKey)
            apiKeyConfigured = true
            apiKeyPresence = .present
        } catch {
            let description = shortError(error)
            if description.contains("Keychain") || description.contains("系统拒绝") {
                apiKeyPresence = .inaccessible
                failParse(
                    message: "Keychain 中有 API Key，但当前构建无权读取。请打开“API Key”重新保存一次，必要时选择 Always Allow。",
                    logError: "keychain_inaccessible"
                )
            } else {
                failParse(message: "读取 Keychain 失败：\(description)", logError: "keychain_failed")
            }
            return
        }

        let prompt: String
        do {
            prompt = try PromptLoader.load()
        } catch {
            failParse(message: "缺少 system_prompt.txt，无法解析", logError: "missing_prompt")
            return
        }

        // Single assembly point: the text source ignores `ocrSections` by
        // construction, so the two sources can never bleed into each other.
        let combinedText = InputComposer.compose(
            source: inputSource,
            emailBody: emailText,
            plainText: plainText,
            ocrSections: ocrSections
        )
        do {
            let response = try await deepSeek.parse(text: combinedText, systemPrompt: prompt, apiKey: apiKey)
            if let error = response.error, !error.isEmpty {
                failParse(message: error, logError: "model_error")
                return
            }
            let events = ParsedEventSanitizer.sanitize(response.events)
            guard !events.isEmpty else {
                failParse(message: "未识别到可确认的事件", logError: "empty_result")
                return
            }
            drafts = DraftFactory.makeDrafts(from: events)
            parseSucceeded = true
            parsedInputSnapshot = currentInputSnapshot()
            notice = "已识别 \(drafts.count) 条候选事件，请逐条核对后再写入"
            errorMessage = nil
            appendParseLog(
                success: true,
                eventCount: drafts.count,
                eventTypes: drafts.map { $0.type.rawValue },
                error: nil
            )
        } catch {
            failParse(message: shortError(error), logError: "deepseek_failed")
        }
    }

    private func failParse(message: String, logError: String) {
        errorMessage = "解析失败：\(message)"
        workStatus = .idle
        appendParseLog(success: false, eventCount: 0, eventTypes: [], error: logError)
    }

    private func appendParseLog(success: Bool, eventCount: Int, eventTypes: [String], error: String?) {
        let duration = parseStartedAt.map { Int(Date().timeIntervalSince($0) * 1_000) }
        let record = LogRecord(
            kind: "parse",
            inputType: inputTypeForParse,
            imageCount: imageCountForParse,
            eventCount: eventCount,
            eventTypes: eventTypes,
            error: error,
            durationMs: duration,
            modifiedFields: []
        )
        appendLog(record)
    }

    // MARK: - Confirmation and writing

    func clearConflict(for id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }), !drafts[index].isWritten else { return }
        if !drafts[index].conflicts.isEmpty || drafts[index].writeAnyway {
            drafts[index].conflicts = []
            drafts[index].writeAnyway = false
        }
    }

    func writeToCalendar() {
        guard !isWriting else { return }
        let targets = drafts.filter { $0.confirmed && !$0.isWritten }
        guard !targets.isEmpty else {
            lastWriteSummary = "没有待写入的已确认事件"
            return
        }
        guard calendarState.canAttemptWrite else {
            errorMessage = calendarPermissionPrompt
            return
        }

        isWriting = true
        lastWriteDetail = ""
        Task {
            defer { isWriting = false }

            if calendarState == .notDetermined || calendarState == .writeOnly {
                do {
                    let granted = try await target.requestAccess()
                    refreshCalendarStatus()
                    if !granted || !calendarState.isGranted {
                        switch writeTarget {
                        case .calendar:
                            lastWriteSummary = calendarState == .writeOnly
                                ? "仅获得写入权限，无法检查冲突，未写入任何事件"
                                : "日历权限未授予，未写入任何事件"
                        case .reminders:
                            lastWriteSummary = "提醒事项权限未授予，未写入任何事件"
                        case .googleCalendar:
                            lastWriteSummary = "Google 授权未完成，未写入任何事件"
                        }
                        return
                    }
                } catch {
                    refreshCalendarStatus()
                    switch writeTarget {
                    case .calendar:
                        lastWriteSummary = "请求日历权限失败，未写入任何事件"
                    case .reminders:
                        lastWriteSummary = "请求提醒事项权限失败，未写入任何事件"
                    case .googleCalendar:
                        lastWriteSummary = "连接 Google 账户失败，未写入任何事件"
                    }
                    lastWriteDetail = shortError(error)
                    return
                }
            }

            var written = 0
            var skippedForConflict = 0
            var conflictCount = 0
            var failureCount = 0
            var failureMessages: [String] = []
            var attemptedTypes: [String] = []
            var modifiedFields = Set<String>()
            target.resetRoutingNotice()

            for id in targets.map(\.id) {
                guard let index = drafts.firstIndex(where: { $0.id == id }), !drafts[index].isWritten else { continue }
                var draft = drafts[index]
                attemptedTypes.append(draft.type.rawValue)
                modifiedFields.formUnion(draft.modifiedFields)

                let validation = draft.validationMessages
                guard validation.isEmpty else {
                    failureCount += 1
                    failureMessages.append("\(draft.title)：\(validation.joined(separator: "、"))")
                    continue
                }

                do {
                    let conflicts = try await target.findConflicts(for: draft)
                    draft.conflicts = conflicts
                    if !conflicts.isEmpty {
                        conflictCount += 1
                    }
                    if !conflicts.isEmpty && !draft.writeAnyway {
                        skippedForConflict += 1
                        drafts[index] = draft
                        continue
                    }
                    // One draft per call keeps the per-card conflict/skip/
                    // failure accounting identical to V1.0.
                    try await target.saveEvents([draft])
                    draft.isWritten = true
                    written += 1
                    drafts[index] = draft
                } catch {
                    failureCount += 1
                    failureMessages.append("\(draft.title)：\(shortError(error))")
                    drafts[index] = draft
                    if let calendarError = error as? TargetProviderError,
                       calendarError == .accessDenied {
                        refreshCalendarStatus()
                    }
                }
            }

            var summary = "已写入 \(written) 条，\(skippedForConflict) 条时间冲突未写入"
            if failureCount > 0 {
                summary += "，\(failureCount) 条未写入（信息不完整或写入失败）"
            }
            lastWriteSummary = summary
            lastWriteDetail = failureMessages.joined(separator: "\n")
            if conflictCount > 0 && skippedForConflict > 0 {
                notice = "发现 \(conflictCount) 条时间冲突：冲突事件已跳过，可在卡片中选择“冲突仍写入”后再次写入。"
            }
            // Calendar routing is best-effort: when the per-type calendar could
            // not be created, the event still lands in the default calendar and
            // the reason is surfaced here instead of failing the write.
            if let routingNotice = target.routingNotice {
                lastWriteDetail = [lastWriteDetail, routingNotice]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                if lastWriteSummary.isEmpty || !lastWriteSummary.contains("回退") {
                    lastWriteSummary += "（已回退到默认日历）"
                }
            }

            appendLog(
                LogRecord(
                    kind: "write",
                    inputType: currentInputType,
                    eventCount: attemptedTypes.count,
                    eventTypes: attemptedTypes,
                    error: failureCount > 0 ? "partial_failure" : nil,
                    modifiedFields: Array(modifiedFields).sorted(),
                    writtenCount: written,
                    conflictCount: conflictCount,
                    skippedConflictCount: skippedForConflict
                )
            )
            refreshStats()
            refreshCalendarStatus()
        }
    }

    func flagMissedEvent() {
        guard parseSucceeded else { return }
        appendLog(
            LogRecord(
                kind: "missed_feedback",
                inputType: currentInputType,
                imageCount: images.count,
                eventCount: drafts.count,
                eventTypes: drafts.map { $0.type.rawValue }
            )
        )
        missedFeedbackSent = true
        notice = "已记录一次漏检反馈（不包含原文或敏感字段），可在最近 14 天统计中查看。"
        refreshStats()
    }

    // MARK: - API key

    func refreshAPIKeyStatus() {
        // Never query Keychain at launch: even an attributes-only probe can
        // summon a system unlock/ACL dialog for an ad-hoc signed local app.
        // The key itself is read only when the user explicitly parses.
        let hasSavedKey = UserDefaults.standard.bool(forKey: Self.apiKeyPresenceKey)
        apiKeyConfigured = hasSavedKey
        apiKeyPresence = hasSavedKey ? .present : .missing
    }

    func saveAPIKey() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            apiKeyMessage = "请输入 API Key"
            apiKeyIsError = true
            return
        }
        do {
            try keychain.saveAPIKey(key)
            UserDefaults.standard.set(true, forKey: Self.apiKeyPresenceKey)
            apiKeyDraft = ""
            apiKeyConfigured = true
            apiKeyPresence = .present
            apiKeyMessage = "已保存到 macOS Keychain（当前构建）"
            apiKeyIsError = false
        } catch {
            apiKeyMessage = shortError(error)
            apiKeyIsError = true
        }
    }

    func deleteAPIKey() {
        do {
            try keychain.deleteAPIKey()
            UserDefaults.standard.set(false, forKey: Self.apiKeyPresenceKey)
            apiKeyDraft = ""
            apiKeyConfigured = false
            apiKeyPresence = .missing
            apiKeyMessage = "已从 Keychain 删除"
            apiKeyIsError = false
        } catch {
            apiKeyMessage = shortError(error)
            apiKeyIsError = true
        }
    }

    // MARK: - Logs and stats

    func refreshStats() {
        logStats = logService?.stats(days: 14) ?? .empty
        logPath = logService?.path ?? ""
    }

    func requestClearLogs() {
        guard logService != nil else {
            exportMessage = "日志服务不可用"
            return
        }
        showClearLogConfirmation = true
    }

    func clearLogs() {
        guard let logService else {
            exportMessage = "日志服务不可用"
            return
        }
        do {
            try logService.clear()
            exportMessage = "本地日志已清空"
            notice = "本地日志已清空；未删除任何其他文件。"
            refreshStats()
        } catch {
            exportMessage = "清空日志失败：\(shortError(error))"
        }
    }

    func exportLogs() {
        guard let logService else {
            exportMessage = "日志服务不可用"
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出最近 30 条日志"
        panel.nameFieldStringValue = "school-event-inbox-log-\(Self.dateStamp()).jsonl"
        if let jsonlType = UTType(filenameExtension: "jsonl") {
            panel.allowedContentTypes = [jsonlType]
        } else {
            panel.allowedContentTypes = [.json]
        }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try logService.exportLast30(to: url)
            exportMessage = "已导出 \(count) 条到 \(url.path)"
            notice = exportMessage
            refreshStats()
        } catch {
            exportMessage = "导出失败：\(shortError(error))"
        }
    }

    func revealLogFolder() {
        guard !logPath.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: logPath)])
    }

    private func appendLog(_ record: LogRecord) {
        guard let logService else { return }
        try? logService.append(record)
    }

    private func shortError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return String(error.localizedDescription.prefix(80))
    }

    private static let apiKeyPresenceKey = "SchoolEventInbox.hasDeepSeekAPIKey"

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }
}
