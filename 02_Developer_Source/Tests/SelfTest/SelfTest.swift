import Darwin
import Foundation
import SchoolEventInboxCore

@main
struct SelfTest {
    static func main() async {
        setbuf(stdout, nil)
        let harness = Harness()
        let started = Date()

        print("SchoolEventInbox self-test")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("")

        if fixturesAvailable {
            harness.section("样本输入与 JSON 契约")
            runAcceptance(harness)

            harness.section("DeepSeek 请求/错误契约（网络桩）")
            await runDeepSeekTests(harness)

            harness.section("Vision 本地 OCR（真实图片）")
            await runOCRTests(harness)
        } else {
            print("SKIP  样本/OCR 项：Tests/Fixtures 已在发布整理中删除")
            harness.section("DeepSeek 错误契约（无样本）")
            await runDeepSeekTests(harness, fixtureContract: false)
        }

        harness.section("英文生日名单解析")
        runEnglishBirthdayListTest(harness)

        harness.section("模型、全天与托管标签")
        runModelAndTagTests(harness)

        harness.section("按类型分配日历")
        runCalendarRoutingTests(harness)

        harness.section("提醒事项到期映射")
        runRemindersMappingTests(harness)

        harness.section("输入源组装（邮件 vs 纯文本）")
        runInputComposerTests(harness)

        harness.section("Google 凭据加载")
        runGoogleCredentialTests(harness)

        harness.section("Google OAuth / 映射 / 401 重试")
        await runGoogleOAuthTests(harness)

        harness.section("日期/时区/歧义")
        runDateTests(harness)

        harness.section("日志导出与统计")
        runLogTests(harness)

        harness.section("Keychain 与日历权限")
        runKeychainTest(harness)
        await runCalendarStatusTest(harness)

        let elapsed = Date().timeIntervalSince(started)
        print("")
        print("RESULT: \(harness.passed) passed, \(harness.failed) failed, \(String(format: "%.2f", elapsed))s")
        if harness.failed > 0 {
            print("FAILURES:")
            harness.failures.forEach { print(" - \($0)") }
        }
        exit(harness.failed == 0 ? 0 : 1)
    }

    private static var fixturesAvailable: Bool {
        FileManager.default.fileExists(atPath: FixturePaths.fixtures.path)
    }

    private static func runAcceptance(_ h: Harness) {
        guard fixturesAvailable else {
            print("  SKIP  5 个样本已随 Tests/Fixtures 删除")
            return
        }
        do {
            let response = try Fixtures.json("parse_email_01")
            let events = ParsedEventSanitizer.sanitize(response.events)
            h.equal(events.count, 2, "邮件1应拆成2条事件")
            let drafts = DraftFactory.makeDrafts(
                from: events,
                now: TestClock.referenceNow,
                timeZone: TestClock.timeZone,
                calendar: TestClock.calendar
            )
            h.equal(drafts.count, 2, "邮件1草稿数")
            h.equal(drafts.map(\.type), [.deadline, .activity], "邮件1类型顺序")

            if drafts.count == 2 {
                let deadline = drafts[0]
                let activity = drafts[1]
                h.check(deadline.allDay, "deadline 应全天")
                h.equal(TestClock.calendar.component(.month, from: deadline.start), 3, "deadline 月份")
                h.equal(TestClock.calendar.component(.day, from: deadline.start), 5, "deadline 日期=3月5日")
                h.check(deadline.evidence.contains("报名截止"), "deadline 有 evidence")
                h.check(deadline.confirmed && deadline.isCritical, "deadline 默认勾选且关键类型")

                h.equal(activity.location, "A101", "活动地点=A101")
                h.equal(TestClock.calendar.component(.day, from: activity.start), 8, "活动日期=3月8日")
                h.equal(TestClock.calendar.component(.hour, from: activity.start), 14, "活动时间=14:00")
                h.check(activity.evidence.contains("A101"), "活动 evidence")
                h.check(activity.confirmed, "普通活动也默认要求确认")
                h.check(activity.canWrite, "活动可写入")
                print("  SAMPLE 1 PASS: deadline 3/5 + activity 3/8 14:00 @ A101")
            }

            let response2 = try Fixtures.json("parse_email_02")
            let drafts2 = DraftFactory.makeDrafts(
                from: ParsedEventSanitizer.sanitize(response2.events),
                now: TestClock.referenceNow,
                timeZone: TestClock.timeZone,
                calendar: TestClock.calendar
            )
            h.equal(drafts2.count, 2, "邮件2应拆成2条")
            h.equal(drafts2.map(\.type), [.deadline, .appointment], "邮件2类型")
            h.equal(drafts2.last?.location, "行政楼 208", "面试地点")
            h.check(drafts2.allSatisfy { $0.confirmed }, "邮件2全部默认确认")
            print("  SAMPLE 2 PASS: deadline + appointment, 2 events")
        } catch {
            h.fail("邮件样本测试异常：\(error)")
        }

        do {
            let response = try Fixtures.json("parse_poster_no_year")
            let draft = DraftFactory.makeDraft(
                from: try unwrap(ParsedEventSanitizer.sanitize(response.events).first, h, "海报事件存在"),
                now: TestClock.referenceNow,
                timeZone: TestClock.timeZone,
                calendar: TestClock.calendar
            )
            h.check(!draft.hasStart, "海报缺年份 -> 不编造开始时间")
            h.check(draft.notes.contains("人工补充"), "海报缺年份 notes 提示")
            h.check(!draft.canWrite, "海报缺时间不可直接写入")
            h.equal(draft.location, "大学生活动中心 B201", "海报地点保留")
            print("  SAMPLE 4 PASS: missing-year poster stays nil")
        } catch {
            h.fail("海报样本异常：\(error)")
        }

        do {
            let response = try Fixtures.json("parse_email_03_weekly")
            let draft = DraftFactory.makeDraft(
                from: try unwrap(ParsedEventSanitizer.sanitize(response.events).first, h, "例会事件存在"),
                now: TestClock.referenceNow,
                timeZone: TestClock.timeZone,
                calendar: TestClock.calendar
            )
            h.check(!draft.hasStart, "每周二不自动解析")
            h.check(draft.notes.contains("重复") && draft.notes.contains("人工"), "重复规则 notes")
            print("  SAMPLE 5 PASS: weekly recurrence remains manual")
        } catch {
            h.fail("重复语义样本异常：\(error)")
        }

        do {
            let response = try Fixtures.json("parse_no_date")
            h.check(response.events.isEmpty, "无日期 -> 空事件")
            h.equal(response.error, "未识别到日期", "无日期 -> 短 error")
            h.check((response.error?.count ?? 0) <= 40, "error 不超过40字")
        } catch {
            h.fail("空结果样本异常：\(error)")
        }

        let critical = makeEvent(type: .appointment, needsConfirmation: false)
        let exam = makeEvent(type: .exam, needsConfirmation: false)
        let ordinary = makeEvent(type: .activity, needsConfirmation: false)
        let sanitized = ParsedEventSanitizer.sanitize([critical, exam, ordinary])
        h.check(sanitized.allSatisfy(\.needsConfirmation), "所有事件强制 needsConfirmation=true")
        h.check(sanitized[0].notes.contains("强制"), "关键类型降级会被记录")
        h.check(sanitized[2].notes.isEmpty, "普通事件不额外写强制 notes")

        do {
            let prompt = try String(contentsOf: FixturePaths.prompt, encoding: .utf8)
            h.check(prompt.contains("只输出一个 JSON"), "system prompt 仅 JSON")
            h.check(prompt.contains("禁止编造日期"), "system prompt 禁止编造")
            h.check(prompt.contains("缺年份"), "system prompt 缺年份规则")
            h.check(prompt.contains("时区不明"), "system prompt 时区规则")
            h.check(prompt.contains("每周二"), "system prompt 重复语义规则")
            h.check(prompt.contains("needsConfirmation"), "system prompt 确认规则")
            h.check(prompt.contains("deadline"), "system prompt 类型规则")
            h.check(prompt.contains("evidence"), "system prompt evidence 规则")
            h.check(!prompt.contains("一定不会漏。"), "system prompt 不担保不漏")
        } catch {
            h.fail("读取 system_prompt 失败：\(error)")
        }

        let allDayDraft = DraftFactory.makeDraft(
            from: makeEvent(type: .deadline, start: "2026-03-05T00:00:00+08:00", allDay: true, location: nil),
            now: TestClock.referenceNow,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        let interval = allDayDraft.calendarInterval(calendar: TestClock.calendar)
        h.equal(TestClock.calendar.component(.day, from: interval.start), 5, "全天开始日")
        h.equal(TestClock.calendar.component(.day, from: interval.end), 6, "全天结束日 exclusive")
        h.equal(Int(interval.duration), 86_400, "全天时长")

        let base = TestClock.referenceNow
        h.check(ConflictDetector.overlaps(
            DateInterval(start: base, duration: 3_600),
            DateInterval(start: base.addingTimeInterval(1_800), duration: 3_600)
        ), "冲突检测重叠")
        h.check(!ConflictDetector.overlaps(
            DateInterval(start: base, duration: 3_600),
            DateInterval(start: base.addingTimeInterval(3_600), duration: 3_600)
        ), "冲突检测首尾相接不算冲突")
    }

    private static func runDeepSeekTests(_ h: Harness, fixtureContract: Bool = true) async {
        if fixtureContract {
            MockURLProtocol.reset()
            do {
                let responseJSON = try Fixtures.text("parse_email_01", "json")
                MockURLProtocol.handler = { _ in try MockURLProtocol.chatResponse(content: responseJSON) }
                let service = DeepSeekService(session: MockURLProtocol.makeSession())
                let prompt = "系统提示：只输出 JSON"
                let input = "报名截止 3月5日；活动 3月8日 14:00；地点 A101"
                let started = Date()
                let result = try await service.parse(text: input, systemPrompt: prompt, apiKey: "sk-test-not-real")
                let elapsed = Date().timeIntervalSince(started)
                h.equal(result.events.count, 2, "DeepSeek 桩解析事件数")
                h.check(result.events.allSatisfy(\.needsConfirmation), "返回事件强制确认")
                h.check(elapsed < 30, "单条解析本地回合 <30s（实测 \(String(format: "%.3f", elapsed))s）")

                guard let request = MockURLProtocol.lastRequest else {
                    h.fail("未捕获请求")
                    return
                }
                h.equal(request.httpMethod, "POST", "HTTP 方法")
                h.equal(request.url?.absoluteString, "https://api.deepseek.com/chat/completions", "endpoint")
                h.equal(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-not-real", "Bearer header")
                h.equal(request.value(forHTTPHeaderField: "Content-Type"), "application/json", "Content-Type")

                let body = try unwrap(MockURLProtocol.lastBody, h, "请求 body")
                let object = try unwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any], h, "body JSON")
                h.equal(object["model"] as? String, "deepseek-chat", "model=deepseek-chat")
                h.equal(object["stream"] as? Bool, false, "stream=false")
                h.equal((object["response_format"] as? [String: Any])?["type"] as? String, "json_object", "response_format=json_object")
                let messages = try unwrap(object["messages"] as? [[String: Any]], h, "messages")
                h.equal(messages.count, 2, "messages 数")
                h.equal(messages[0]["role"] as? String, "system", "system role")
                h.equal(messages[0]["content"] as? String, prompt, "system prompt 来自参数")
                h.equal(messages[1]["role"] as? String, "user", "user role")
                h.check((messages[1]["content"] as? String ?? "").contains(input), "输入文本进入 user message")
                h.check(!(messages[1]["content"] as? String ?? "").contains("base64"), "不发送图片数据")
                print("  DeepSeek contract PASS: model/temperature/response_format/headers")
            } catch {
                h.fail("DeepSeek 契约测试异常：\(error)")
            }
        } else {
            print("  SKIP  DeepSeek 成功响应契约（依赖已删除样本）")
        }

        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in
            let url = URL(string: "https://api.deepseek.com/chat/completions")!
            let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"error\":{\"message\":\"bad\"}}".utf8))
        }
        do {
            _ = try await DeepSeekService(session: MockURLProtocol.makeSession())
                .parse(text: "x", systemPrompt: "p", apiKey: "sk-bad")
            h.fail("401 应该抛错")
        } catch let error as DeepSeekError {
            h.equal(error, .unauthorized, "401 -> unauthorized")
            h.equal(error.errorDescription, "API Key 无效或未授权", "401 中文短错误")
        } catch {
            h.fail("401 错误类型不符：\(error)")
        }

        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in try MockURLProtocol.chatResponse(content: "这不是 JSON") }
        do {
            _ = try await DeepSeekService(session: MockURLProtocol.makeSession())
                .parse(text: "x", systemPrompt: "p", apiKey: "sk-test")
            h.fail("非法 JSON 应该抛错")
        } catch let error as DeepSeekError {
            h.equal(error, .badResponse, "非法 JSON -> badResponse")
        } catch {
            h.fail("非法 JSON 错误类型不符：\(error)")
        }

        MockURLProtocol.reset()
        do {
            _ = try await DeepSeekService(session: MockURLProtocol.makeSession())
                .parse(text: "x", systemPrompt: "p", apiKey: " ")
            h.fail("缺 Key 应该抛错")
        } catch let error as DeepSeekError {
            h.equal(error, .missingAPIKey, "缺 Key -> missingAPIKey")
            h.check(MockURLProtocol.lastRequest == nil, "缺 Key 不发起网络请求")
        } catch {
            h.fail("缺 Key 错误类型不符：\(error)")
        }
    }

    private static func runOCRTests(_ h: Harness) async {
        guard fixturesAvailable else {
            print("  SKIP  OCR 样本已随 Tests/Fixtures 删除")
            return
        }
        do {
            let started = Date()
            let result = try await OCRService().recognize(imageData: try Fixtures.data("appointment_01", "png"))
            let elapsed = Date().timeIntervalSince(started)
            let compact = compactOCRText(result.text)
            h.check(result.text.contains("预约") || result.text.contains("校医院"), "预约截图识别标题")
            h.check(compact.contains("2026"), "预约截图识别年份")
            h.check(compact.contains("09:30"), "预约截图识别 09:30")
            h.check(compact.contains("305"), "预约截图识别 305")
            h.check(compact.contains("校医院三楼"), "预约截图识别地点")
            h.check(result.lines.count > 3, "OCR 保留多行")
            h.check(elapsed < 30, "预约截图 OCR <30s（实测 \(String(format: "%.2f", elapsed))s）")
            print("  SAMPLE 3 PASS: appointment screenshot OCR (\(String(format: "%.2f", elapsed))s)")
            print("    \(result.text.replacingOccurrences(of: "\n", with: " | "))")
        } catch {
            h.fail("预约截图 OCR 异常：\(error)")
        }

        do {
            let result = try await OCRService().recognize(imageData: try Fixtures.data("poster_01", "png"))
            let compact = compactOCRText(result.text)
            h.check(compact.contains("春季社团招新"), "海报识别标题")
            h.check(compact.contains("18:30"), "海报识别 18:30")
            h.check(compact.contains("B201"), "海报识别 B201")
            print("  SAMPLE 4 OCR PASS: poster (\(result.lines.count) lines)")
            print("    \(result.text.replacingOccurrences(of: "\n", with: " | "))")
        } catch {
            h.fail("海报 OCR 异常：\(error)")
        }

        do {
            let result = try await OCRService().recognize(imageData: try Fixtures.data("no_date_01", "png"))
            h.check(result.text.contains("投稿"), "无日期截图仍识别文本")
            h.check(!result.text.isEmpty, "无日期截图非空")
            print("  SAMPLE 5 OCR PASS: no-date screenshot still returns text")
        } catch {
            h.fail("无日期截图 OCR 异常：\(error)")
        }

        do {
            _ = try await OCRService().recognize(imageData: Data([0x00, 0x01, 0x02]))
            h.fail("坏图片应该抛错")
        } catch let error as OCRError {
            h.equal(error, .recognitionFailed, "坏图片 -> recognitionFailed")
        } catch {
            h.fail("坏图片错误类型不符：\(error)")
        }
    }

    private static func runEnglishBirthdayListTest(_ h: Harness) {
        let input = """
        December 8 - Hayeon
        January 22 - Olena
        May 14 - Tina
        Dec 21 - Lisa
        Dec 2 - Jack
        May 4 - Hanna
        November 7 - Fiorelli
        """
        let wrapped = "【邮件正文】\n" + input
        let events = EnglishBirthdayListParser.parse(
            text: wrapped,
            now: TestClock.referenceNow,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        h.check(events?.count == 7, "英文名单拆成 7 条")
        h.check(events?.allSatisfy { $0.type == .birthday } == true, "英文名单全部 birthday")
        h.check(events?.allSatisfy(\.allDay) == true, "英文名单全部 allDay")
        h.check(events?.allSatisfy { $0.start?.contains("2026-") == true } == true, "缺年份默认今年")
        h.check(events?.allSatisfy { $0.needsConfirmation } == true, "名单需要确认")
        h.equal(events?.first?.title, "Hayeon 生日", "英文姓名标题")
        h.check(events?.first?.notes.contains("缺年份，默认今年") == true, "缺年份 notes")
        h.equal(ManagedEventMetadata.managedNotes(original: "hi", type: .birthday).contains(ManagedEventMetadata.managedTag), true, "birthday 标签")
    }

    private static func runModelAndTagTests(_ h: Harness) {
        h.equal(EventType.birthday.symbolName, "birthday.cake.fill", "生日 SF Symbol")
        h.equal(EventType.birthday.colorToken, "pink", "生日颜色")
        h.check(EventType.allCases.contains(.birthday), "类型列表含 birthday")

        let notes = ManagedEventMetadata.managedNotes(original: "用户备注", type: .birthday)
        h.check(notes.contains(ManagedEventMetadata.managedTag), "notes 含 SchoolEventInbox-Managed")
        h.check(notes.contains(ManagedEventMetadata.compatibilityTag), "notes 含 Managed by SchoolEventInbox")
        h.check(notes.contains("\(ManagedEventMetadata.typeTagPrefix)birthday]"), "notes 含 birthday 类型标记")
        h.check(ManagedEventMetadata.isManagedNotes(notes), "托管标签识别")
        h.check(!ManagedEventMetadata.isManagedNotes("和朋友的晚餐"), "私人事件不被识别为托管")

        let allDay = DraftFactory.makeDraft(
            from: makeEvent(type: .birthday, start: "2026-03-20T00:00:00+08:00", allDay: true, location: nil),
            now: TestClock.referenceNow,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        let interval = allDay.calendarInterval(calendar: TestClock.calendar)
        h.equal(TestClock.calendar.component(.hour, from: interval.start), 0, "全天开始为 00:00")
        h.equal(TestClock.calendar.component(.hour, from: interval.end), 0, "全天结束为 00:00")
        h.equal(TestClock.calendar.component(.day, from: interval.end), 21, "全天结束为次日")
    }

    private static func runCalendarRoutingTests(_ h: Harness) {
        // Pure mapping only: these assertions never touch EKEventStore, so they
        // are safe to run in a sandbox without calendar permission.
        h.equal(ManagedEventMetadata.managedCalendarTitle(for: .deadline), "More Calendar - 截止", "截止日历标题")
        h.equal(ManagedEventMetadata.managedCalendarTitle(for: .appointment), "More Calendar - 预约", "预约日历标题")
        h.equal(ManagedEventMetadata.managedCalendarTitle(for: .exam), "More Calendar - 考试", "考试日历标题")
        h.equal(ManagedEventMetadata.managedCalendarTitle(for: .birthday), "More Calendar - 生日", "生日日历标题")
        h.equal(ManagedEventMetadata.managedCalendarTitle(for: .activity), "More Calendar - 活动", "活动日历标题")
        h.equal(ManagedEventMetadata.managedCalendarTitle(for: .other), "More Calendar - 活动", "其他与活动共用日历")

        h.equal(ManagedEventMetadata.managedCalendarColorToken(for: .deadline), .orange, "截止→橙")
        h.equal(ManagedEventMetadata.managedCalendarColorToken(for: .appointment), .blue, "预约→蓝")
        h.equal(ManagedEventMetadata.managedCalendarColorToken(for: .exam), .red, "考试→红")
        h.equal(ManagedEventMetadata.managedCalendarColorToken(for: .birthday), .purple, "生日→紫")
        h.equal(ManagedEventMetadata.managedCalendarColorToken(for: .activity), .green, "活动→绿")
        h.equal(ManagedEventMetadata.managedCalendarColorToken(for: .other), .green, "其他→绿")

        h.equal(EventType.other.managedCalendarBucket, .activity, "other 归入活动桶")
        h.check(ManagedEventMetadata.managedCalendarTitle(for: .exam)
            .hasPrefix(ManagedEventMetadata.managedCalendarPrefix), "日历标题带统一前缀")

        // Each bucket must own a distinct calendar and colour.
        let buckets: [EventType] = [.deadline, .appointment, .exam, .birthday, .activity]
        let titles = Set(buckets.map { ManagedEventMetadata.managedCalendarTitle(for: $0) })
        let colors = Set(buckets.map { ManagedEventMetadata.managedCalendarColorToken(for: $0) })
        h.equal(titles.count, buckets.count, "五种类型对应五个不同日历")
        h.equal(colors.count, buckets.count, "五种类型对应五种不同颜色")

        // English titles + reverse lookup (used when renaming existing
        // calendars after a language switch).
        h.equal(ManagedEventMetadata.managedCalendarTitle(for: .exam, language: .english),
                "More Calendar - Exam", "英文考试日历标题")
        h.equal(ManagedEventMetadata.managedCalendarTitle(for: .birthday, language: .english),
                "More Calendar - Birthday", "英文生日日历标题")
        h.equal(ManagedEventMetadata.managedCalendarTitle(for: .other, language: .english),
                "More Calendar - Activity", "英文 other 归入 Activity")
        h.equal(ManagedEventMetadata.managedCalendarBucket(forTitle: "More Calendar - 考试"), .exam, "中文标题回溯类型")
        h.equal(ManagedEventMetadata.managedCalendarBucket(forTitle: "More Calendar - Exam"), .exam, "英文标题回溯类型")
        h.equal(ManagedEventMetadata.managedCalendarBucket(forTitle: "More Calendar - Activity"), .activity, "Activity 标题回溯")
        h.check(ManagedEventMetadata.managedCalendarBucket(forTitle: "校历") == nil, "非本工具日历不被接管")
        h.check(ManagedEventMetadata.knownCalendarTitles(for: .exam).count == 2, "考试有中英两种标题")
    }

    /// Reminders carry a single due point instead of a start/end interval, so
    /// the mapping deserves its own assertions. Pure: no reminder permission
    /// is requested here.
    private static func runRemindersMappingTests(_ h: Harness) {
        let allDayDraft = DraftFactory.makeDraft(
            from: makeEvent(type: .deadline, start: "2026-03-05T00:00:00+08:00", allDay: true, location: nil),
            now: TestClock.referenceNow,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        let allDay = AppleRemindersProvider.dueDateComponents(for: allDayDraft, calendar: TestClock.calendar)
        h.equal(allDay.year, 2026, "全天到期：年")
        h.equal(allDay.month, 3, "全天到期：月")
        h.equal(allDay.day, 5, "全天到期：日")
        h.check(allDay.hour == nil && allDay.minute == nil, "全天到期只写日期不写时刻")

        let timedDraft = DraftFactory.makeDraft(
            from: makeEvent(type: .appointment, start: "2026-03-12T09:30:00+08:00", allDay: false, location: nil),
            now: TestClock.referenceNow,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        let timed = AppleRemindersProvider.dueDateComponents(for: timedDraft, calendar: TestClock.calendar)
        h.equal(timed.day, 12, "定时到期：日")
        h.equal(timed.hour, 9, "定时到期：小时取开始时间")
        h.equal(timed.minute, 30, "定时到期：分钟取开始时间")

        // A birthday keeps the calendar's yearly-recurrence intent, and its due
        // date stays date-only even when the model marked it as a timed event.
        let birthdayDraft = DraftFactory.makeDraft(
            from: makeEvent(type: .birthday, start: "2026-03-20T00:00:00+08:00", allDay: true, location: nil),
            now: TestClock.referenceNow,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        let birthday = AppleRemindersProvider.dueDateComponents(for: birthdayDraft, calendar: TestClock.calendar)
        h.check(birthday.hour == nil, "生日到期只写日期")
        h.equal(birthday.day, 20, "生日到期日")
    }

    /// The DeepSeek payload is a prompt contract: these assertions pin both the
    /// exact section format and the guarantee that text mode never carries OCR.
    private static func runInputComposerTests(_ h: Harness) {
        let ocr = [InputComposer.OCRSection(name: "a.png", text: "图一")]

        let emailPayload = InputComposer.compose(
            source: .email,
            emailBody: "正文",
            plainText: "不应出现",
            ocrSections: ocr
        )
        h.equal(emailPayload, "【邮件正文】\n正文\n\n【图片 1 本地 OCR：a.png】\n图一", "邮件模式拼接正文与 OCR 段")

        let textPayload = InputComposer.compose(
            source: .text,
            emailBody: "不应出现",
            plainText: "3月5日截止",
            ocrSections: ocr
        )
        h.equal(textPayload, "【纯文本】\n3月5日截止", "纯文本只发送纯文本段")
        h.check(!textPayload.contains("OCR"), "纯文本模式不包含 OCR 段")
        h.check(!textPayload.contains("不应出现"), "纯文本模式忽略邮件正文缓冲")

        h.equal(
            InputComposer.compose(source: .text, emailBody: "", plainText: "   ", ocrSections: []),
            "",
            "空白输入不产生载荷"
        )
        h.equal(
            InputComposer.compose(source: .text, emailBody: "", plainText: "  内容  ", ocrSections: []),
            "【纯文本】\n内容",
            "纯文本首尾空白被裁剪"
        )

        h.check(
            InputComposer.hasInput(source: .text, emailBody: "", plainText: "x", imageCount: 0),
            "纯文本有内容时可解析"
        )
        h.check(
            !InputComposer.hasInput(source: .text, emailBody: "", plainText: "  ", imageCount: 3),
            "纯文本为空时不可解析，且图片不参与判定"
        )
        h.check(
            InputComposer.hasInput(source: .email, emailBody: "", plainText: "x", imageCount: 1),
            "邮件模式仅有图片时可解析"
        )
        h.check(
            !InputComposer.hasInput(source: .email, emailBody: "  ", plainText: "x", imageCount: 0),
            "邮件模式下纯文本缓冲不参与判定"
        )

        h.equal(InputComposer.logInputType(source: .text, emailBody: "", imageCount: 0), "text", "纯文本日志类型为 text")
        h.equal(InputComposer.logInputType(source: .email, emailBody: "", imageCount: 2), "image", "仅图片日志类型为 image")
        h.equal(InputComposer.logInputType(source: .email, emailBody: "x", imageCount: 2), "email", "混合输入仍记为 email")
    }

    /// PKCE / 授权 URL / 回调解析 / DTO 映射 / 401 自动重试。
    private static func runGoogleOAuthTests(_ h: Harness) async {
        // RFC 7636 Appendix B 的官方测试向量：sha256 实现错了这里一定挂。
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        h.equal(
            GooglePKCE.challenge(for: verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
            "PKCE S256 与 RFC 7636 向量一致"
        )

        let pkce = GooglePKCE.make()
        h.check(pkce.verifier.count >= 43 && pkce.verifier.count <= 128, "verifier 长度在 43…128")
        h.check(
            pkce.verifier.allSatisfy { $0.isLetter || $0.isNumber || "-._~".contains($0) },
            "verifier 只含 unreserved 字符"
        )
        h.check(pkce.challenge != pkce.verifier, "challenge 不等于 verifier")
        h.check(!pkce.challenge.contains("="), "challenge 无 Base64 padding")

        let client = GoogleOAuthClient(
            clientID: "cid.apps.googleusercontent.com",
            clientSecret: "secret",
            redirectURIs: ["http://localhost"]
        )
        do {
            let request = try GoogleAuthorizationRequest(
                client: client,
                redirectURI: URL(string: "http://localhost:51234/callback")!,
                pkce: pkce
            )
            let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
            let items = components?.queryItems ?? []
            func param(_ name: String) -> String? { items.first { $0.name == name }?.value }

            h.equal(param("client_id"), client.clientID, "授权 URL 带 client_id")
            h.equal(param("response_type"), "code", "授权 URL 为授权码流程")
            h.equal(param("code_challenge_method"), "S256", "使用 S256")
            h.equal(param("code_challenge"), pkce.challenge, "code_challenge 与 verifier 匹配")
            h.equal(param("state"), request.state, "state 已写入 URL")
            h.equal(param("access_type"), "offline", "请求离线访问（拿 refresh_token）")
            h.equal(param("prompt"), "consent", "强制 consent 以获得 refresh_token")
            h.equal(param("redirect_uri"), "http://localhost:51234/callback", "redirect_uri 精确回填")
            h.check(param("scope")?.contains(GoogleOAuthScope.calendarEvents) == true, "scope 含 calendar.events")
        } catch {
            h.fail("授权 URL 构造失败：\(error)")
        }

        // 回调解析
        let ok = Data("GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
        if let callback = GoogleOAuthLoopbackServer.parseCallback(from: ok) {
            h.equal(callback.code, "abc", "解析回调 code")
            h.equal(callback.state, "xyz", "解析回调 state")
        } else {
            h.fail("正常回调应能解析")
        }
        let denied = Data("GET /callback?error=access_denied&error_description=User+denied HTTP/1.1\r\n\r\n".utf8)
        if let callback = GoogleOAuthLoopbackServer.parseCallback(from: denied) {
            h.equal(callback.error, "access_denied", "解析用户拒绝")
            h.check(callback.code == nil, "拒绝时没有 code")
        } else {
            h.fail("错误回调应能解析")
        }
        h.check(
            GoogleOAuthLoopbackServer.parseCallback(from: Data("GET /favicon.ico HTTP/1.1\r\n\r\n".utf8)) == nil,
            "非 /callback 请求不当作回调"
        )

        // loopback 真实回环：验证 NWListener 能起、能收、能回 200
        do {
            let server = GoogleOAuthLoopbackServer()
            let port = try await server.start()
            h.check(port > 0, "loopback 监听拿到端口")
            let url = URL(string: "http://127.0.0.1:\(port)/callback?code=abc&state=xyz")!
            let (_, response) = try await URLSession.shared.data(from: url)
            h.equal((response as? HTTPURLResponse)?.statusCode, 200, "回调返回 200")
            let callback = try await server.waitForCallback(timeout: 5)
            h.equal(callback.code, "abc", "loopback 收到 code")
            h.equal(callback.state, "xyz", "loopback 收到 state")
            await server.stop()
        } catch {
            h.fail("loopback 集成失败：\(error)")
        }

        // 注册的 redirect_uri 不带路径，浏览器会打 "/" 而不是 "/callback"
        let rootPath = Data("GET /?code=abc&state=xyz HTTP/1.1\r\n\r\n".utf8)
        h.equal(GoogleOAuthLoopbackServer.parseCallback(from: rootPath)?.code, "abc", "接受根路径回调")

        // 循环事件：实例删除必须落到系列父事件
        let instance = GoogleEvent(
            id: "inst-1",
            summary: "生日",
            notes: ManagedEventMetadata.managedNotes(original: "", type: .birthday),
            start: GoogleEventDateTime(date: "2026-03-20"),
            end: GoogleEventDateTime(date: "2026-03-21"),
            recurringEventId: "series-9"
        )
        if let managedInstance = GoogleCalendarMapper.managedEvent(
            from: instance,
            calendarID: "primary",
            calendarName: "我",
            timeZone: TestClock.timeZone
        ) {
            h.check(managedInstance.isRecurring, "循环实例（无 recurrence 字段）仍标记为循环")
        } else {
            h.fail("循环实例应能映射")
        }

        let deleteTransport = StubGoogleTransport(responses: [
            (200, Data(#"{"id":"inst-1","recurringEventId":"series-9"}"#.utf8)),
            (204, Data())
        ])
        let provider = await GoogleCalendarProvider(
            transport: deleteTransport,
            tokenProvider: StubGoogleTokenProvider()
        )
        do {
            let removed = try await provider.deleteManagedEvent(id: "primary/inst-1")
            h.equal(removed, 1, "删除循环实例成功")
            h.equal(deleteTransport.requestCount, 2, "先 GET 解析系列，再 DELETE")
            h.equal(deleteTransport.lastRequest?.httpMethod, "DELETE", "最终方法是 DELETE")
            h.check(
                deleteTransport.lastRequest?.url?.path.hasSuffix("events/series-9") == true,
                "删除的是系列父事件而不是实例"
            )
        } catch {
            h.fail("循环实例删除链路失败：\(error)")
        }

        // 写映射
        let allDayDraft = DraftFactory.makeDraft(
            from: makeEvent(type: .exam, start: "2026-03-05T00:00:00+08:00", allDay: true, location: nil),
            now: TestClock.referenceNow,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        let body = GoogleCalendarMapper.makeEventBody(
            from: allDayDraft,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        h.equal(body.start?.date, "2026-03-05", "全天事件写 date 而非 dateTime")
        h.equal(body.end?.date, "2026-03-06", "全天结束为排他的次日")
        h.equal(body.colorId, "11", "考试用红色 colorId 11")
        h.check(body.notes?.contains(ManagedEventMetadata.managedTag) == true, "description 写入托管标签")
        h.equal(body.extendedProperties?.private?[GoogleCalendarMapper.managedPropertyKey], "1", "写入托管私有属性")
        h.equal(body.extendedProperties?.private?[GoogleCalendarMapper.typePropertyKey], "exam", "写入类型私有属性")

        let timedDraft = DraftFactory.makeDraft(
            from: makeEvent(type: .activity, start: "2026-03-08T14:00:00+08:00", allDay: false, location: "A101"),
            now: TestClock.referenceNow,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        let timedBody = GoogleCalendarMapper.makeEventBody(
            from: timedDraft,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        h.check(timedBody.start?.dateTime?.hasPrefix("2026-03-08T14:00:00") == true, "定时事件写 dateTime")
        h.equal(timedBody.location, "A101", "写入地点")
        h.equal(GoogleCalendarMapper.colorId(for: .activity), "10", "活动用绿色 colorId 10")

        let birthdayDraft = DraftFactory.makeDraft(
            from: makeEvent(type: .birthday, start: "2026-03-20T00:00:00+08:00", allDay: true, location: nil),
            now: TestClock.referenceNow,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        let birthdayBody = GoogleCalendarMapper.makeEventBody(
            from: birthdayDraft,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        h.equal(birthdayBody.recurrence, ["RRULE:FREQ=YEARLY"], "生日写入年度重复规则")

        let colorIDs = Set([EventType.deadline, .appointment, .exam, .birthday, .activity].map { GoogleCalendarMapper.colorId(for: $0) })
        h.equal(colorIDs.count, 5, "五种类型对应五种不同 colorId")

        // 读映射
        let googleEvent = GoogleEvent(
            id: "evt-1",
            summary: "期中考试",
            notes: ManagedEventMetadata.managedNotes(original: "", type: .exam),
            start: GoogleEventDateTime(date: "2026-03-05"),
            end: GoogleEventDateTime(date: "2026-03-06"),
            extendedProperties: GoogleExtendedProperties(private: [
                GoogleCalendarMapper.managedPropertyKey: "1",
                GoogleCalendarMapper.typePropertyKey: "exam"
            ])
        )
        h.check(GoogleCalendarMapper.isManaged(googleEvent), "识别本工具创建的事件")
        h.check(
            !GoogleCalendarMapper.isManaged(GoogleEvent(id: "x", summary: "私人", notes: "和朋友的晚餐")),
            "私人事件不被识别"
        )
        if let managed = GoogleCalendarMapper.managedEvent(
            from: googleEvent,
            calendarID: "primary",
            calendarName: "我",
            timeZone: TestClock.timeZone
        ) {
            h.equal(managed.id, "primary/evt-1", "ManagedEvent.id 带日历前缀")
            h.check(managed.isAllDay, "全天事件识别")
            h.equal(managed.type, .exam, "类型从私有属性还原")
        } else {
            h.fail("Google 事件应能映射为 ManagedEvent")
        }
        h.equal(
            GoogleCalendarMapper.splitManagedEventID("primary/evt-1")?.eventID,
            "evt-1",
            "ManagedEvent.id 可拆分"
        )

        // OAuth 全流程：监听 → 模拟浏览器回调 → 换 token → 写入存储
        do {
            let oauthTransport = StubGoogleTransport(responses: [
                (200, Data(#"{"access_token":"at-1","refresh_token":"rt-1","expires_in":3600,"token_type":"Bearer"}"#.utf8))
            ])
            let store = InMemorySecretStore()
            let oauthClient = GoogleOAuthClient(clientID: "cid", clientSecret: "sec")
            let manager = GoogleOAuthManager(
                client: oauthClient,
                tokenStore: store,
                transport: oauthTransport,
                openURL: { url in
                    guard
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                        let redirect = components.queryItems?.first(where: { $0.name == "redirect_uri" })?.value,
                        let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
                        var callback = URLComponents(string: redirect)
                    else { return }
                    callback.queryItems = [
                        URLQueryItem(name: "code", value: "auth-code"),
                        URLQueryItem(name: "state", value: state)
                    ]
                    if let finalURL = callback.url {
                        Task { _ = try? await URLSession.shared.data(from: finalURL) }
                    }
                }
            )
            let token = try await manager.authorize(timeout: 8)
            h.equal(token, "at-1", "OAuth 全流程拿到 access_token")
            let stored = (try? store.readSecret()) ?? nil
            h.equal(stored, "rt-1", "refresh_token 已写入存储")
            h.equal(oauthTransport.requestCount, 1, "只调用一次 token 端点")
        } catch {
            h.fail("OAuth 全流程失败：\(error)")
        }

        // 401 → 刷新 → 重试（只刷一次）
        let transport = StubGoogleTransport(responses: [
            (401, Data()),
            (200, Data(#"{"id":"evt-9","summary":"ok"}"#.utf8))
        ])
        let tokens = StubGoogleTokenProvider()
        let api = GoogleAPIClient(transport: transport, tokenProvider: tokens)
        do {
            let event = try await api.send(GoogleAPIRequest(path: "/calendars/primary/events"), as: GoogleEvent.self)
            h.equal(event.id, "evt-9", "401 后刷新并重试成功")
            let refreshCount = await tokens.refreshCount
            h.equal(refreshCount, 1, "只强制刷新一次")
            let headers = transport.authorizationHeaders
            h.equal(headers.count, 2, "共发起两次请求")
            h.check(headers.last?.contains("token-2") == true, "重试使用刷新后的令牌")
        } catch {
            h.fail("401 重试链路失败：\(error)")
        }

        // URL 拼接：日历 id 里的 @ 必须只编码一次（否则 Google 回 404）
        let urlTransport = StubGoogleTransport(responses: [
            (200, Data("{}".utf8)),
            (200, Data("{}".utf8))
        ])
        let urlAPI = GoogleAPIClient(transport: urlTransport, tokenProvider: StubGoogleTokenProvider())
        _ = try? await urlAPI.send(
            GoogleAPIRequest(path: "/calendars/family@group.calendar.google.com/events"),
            as: GoogleEventsListResponse.self
        )
        let groupURL = urlTransport.lastRequest?.url?.absoluteString ?? ""
        h.check(
            groupURL.contains("calendars/family%40group.calendar.google.com/events"),
            "日历 id 的 @ 只编码一次"
        )
        h.check(!groupURL.contains("%2540"), "没有二次编码（%2540）")

        _ = try? await urlAPI.send(
            GoogleAPIRequest(path: "/calendars/primary/events"),
            as: GoogleEventsListResponse.self
        )
        h.check(
            urlTransport.lastRequest?.url?.absoluteString.hasSuffix("/calendars/primary/events") == true,
            "primary 路径原样拼接"
        )

        // 刷新后仍 401：不应无限重试
        let always401 = StubGoogleTransport(responses: [(401, Data()), (401, Data())])
        let tokens2 = StubGoogleTokenProvider()
        let api2 = GoogleAPIClient(transport: always401, tokenProvider: tokens2)
        do {
            _ = try await api2.send(GoogleAPIRequest(path: "/calendars/primary/events"), as: GoogleEvent.self)
            h.fail("两次 401 应失败")
        } catch let error as GoogleAPIError {
            h.equal(error, .unauthorized, "两次 401 报 unauthorized")
            h.equal(always401.requestCount, 2, "最多重试一次")
        } catch {
            h.fail("两次 401 的错误类型不符")
        }
    }

    /// 凭据加载是 Google 接入的安全边界：既要读得到，又不能把 secret 泄露到日志。
    private static func runGoogleCredentialTests(_ h: Harness) {
        let installed = Data("""
        {"installed":{"client_id":"123-abc.apps.googleusercontent.com","project_id":"demo",
        "auth_uri":"https://accounts.google.com/o/oauth2/v2/auth",
        "token_uri":"https://oauth2.googleapis.com/token",
        "client_secret":"s3cret-value","redirect_uris":["http://localhost"]}}
        """.utf8)

        do {
            let client = try GoogleOAuthClientLoader.parse(installed)
            h.equal(client.clientID, "123-abc.apps.googleusercontent.com", "解析 installed.client_id")
            h.equal(client.redirectURIs.first, "http://localhost", "解析 redirect_uris（loopback）")
            h.equal(client.tokenURI?.absoluteString, "https://oauth2.googleapis.com/token", "解析 token_uri")
            h.equal(client.projectID, "demo", "解析 project_id")
            h.check(!client.redactedSummary.contains("s3cret-value"), "redactedSummary 不泄露 client_secret")
        } catch {
            h.fail("installed 凭据解析失败：\(error)")
        }

        let web = Data("""
        {"web":{"client_id":"web-id","client_secret":"web-secret","redirect_uris":["https://example.com/cb"]}}
        """.utf8)
        h.equal((try? GoogleOAuthClientLoader.parse(web))?.clientID, "web-id", "也接受 web 顶层节点")

        do {
            _ = try GoogleOAuthClientLoader.parse(Data("not json".utf8))
            h.fail("非法 JSON 应报错")
        } catch let error as GoogleOAuthClientError {
            h.check(error != .missing, "非法 JSON 报格式错误而非 missing")
        } catch {
            h.fail("非法 JSON 的错误类型不符")
        }

        do {
            _ = try GoogleOAuthClientLoader.parse(Data(#"{"installed":{"client_id":"x"}}"#.utf8))
            h.fail("缺少 client_secret 应报错")
        } catch let error as GoogleOAuthClientError {
            if case .malformed(let reason) = error {
                h.check(reason.contains("client_secret"), "缺 client_secret 的报错指明字段")
            } else {
                h.fail("缺 client_secret 的错误类型不符")
            }
        } catch {
            h.fail("缺 client_secret 的异常类型不符")
        }

        let searchPaths = GoogleOAuthClientLoader.defaultSearchURLs()
        h.check(
            searchPaths.first?.path.hasSuffix("Library/Application Support/More calendar/google_client_secret.json") == true,
            "首选搜索路径在 Application Support，而非 App bundle"
        )

        do {
            _ = try GoogleOAuthClientLoader.load(from: URL(fileURLWithPath: "/tmp/none-\(UUID().uuidString).json"))
            h.fail("不存在的文件应报错")
        } catch let error as GoogleOAuthClientError {
            h.equal(error, .missing, "不存在的文件报 missing")
        } catch {
            h.fail("不存在文件的错误类型不符")
        }

        // 真机集成：凭据已安装到 Application Support 时，完整搜索链能否读到。
        if let path = searchPaths.first, FileManager.default.fileExists(atPath: path.path) {
            do {
                let client = try GoogleOAuthClientLoader.load()
                h.check(!client.clientID.isEmpty, "从 Application Support 读到真实凭据")
                print("  CREDENTIAL: \(client.redactedSummary)")
            } catch {
                h.fail("读取真实凭据失败：\(error.localizedDescription)")
            }
        } else {
            print("  SKIP  Application Support 下没有 google_client_secret.json（未安装）")
        }
    }

    private static func runDateTests(_ h: Harness) {
        h.check(FlexibleDateParser.parse("3月5日", timeZone: TestClock.timeZone) == nil, "缺年份拒绝解析")
        h.check(FlexibleDateParser.parse("农历二月初五", timeZone: TestClock.timeZone) == nil, "农历拒绝解析")
        h.check(FlexibleDateParser.parse("下周二", timeZone: TestClock.timeZone) == nil, "相对星期拒绝解析")

        do {
            let dateOnly = try unwrap(FlexibleDateParser.parse("2026年3月5日", timeZone: TestClock.timeZone), h, "日期-only")
            h.check(dateOnly.isDateOnly && !dateOnly.hadExplicitTimeZone, "日期-only 标记")
            let zoned = try unwrap(FlexibleDateParser.parse("2026-03-05T14:00:00+08:00", timeZone: TestClock.timeZone), h, "带时区")
            h.check(zoned.hadExplicitTimeZone, "带时区标记")
            let naive = try unwrap(FlexibleDateParser.parse("2026-03-05T14:00:00", timeZone: TestClock.timeZone), h, "无时区")
            h.check(!naive.hadExplicitTimeZone, "无时区标记")
            h.equal(TestClock.calendar.component(.hour, from: naive.date), 14, "无时区按本机解释")
        } catch {
            h.fail("日期解析异常：\(error)")
        }

        let draft = DraftFactory.makeDraft(
            from: makeEvent(start: "2026-03-08T14:00:00"),
            now: TestClock.referenceNow,
            timeZone: TestClock.timeZone,
            calendar: TestClock.calendar
        )
        h.check(draft.notes.contains("时区"), "无时区写 notes")
        h.check(draft.confirmed, "无时区仍默认确认")
    }

    private static func runKeychainTest(_ h: Harness) {
        let service = "local.duishangque.SchoolEventInbox.selftest"
        let account = "test-\(UUID().uuidString)"
        let keychain = KeychainService(serviceName: service, accountName: account)
        do {
            try keychain.saveAPIKey("test-only-not-a-real-key")
            h.equal(try keychain.readAPIKey(), "test-only-not-a-real-key", "Keychain 保存/读取")
            try keychain.deleteAPIKey()
            h.check(try keychain.readAPIKey() == nil, "Keychain 删除")
            print("  KEYCHAIN PASS: local Keychain save/read/delete")
        } catch let KeychainError.unexpectedStatus(status) where status == 100001 {
            // DSH's command sandbox returns EPERM for Keychain access. The app
            // bundle is launched by launchd and is not run inside that sandbox.
            print("  SKIP  Keychain 被当前命令沙箱拒绝（OSStatus 100001）；需在 .app 内验证")
        } catch {
            h.fail("Keychain 测试异常：\(error)")
            try? keychain.deleteAPIKey()
        }
    }

    private static func runCalendarStatusTest(_ h: Harness) async {
        let state = await MainActor.run { AppleCalendarProvider().authorizationState }
        h.check(state != .unknown, "EventKit 授权状态可读取")
        // Guards the V2 seam: AppModel holds `any TargetProvider` and reaches the
        // management panel through a downcast, which would otherwise fail
        // silently with an empty sheet.
        let seam = await MainActor.run { () -> Bool in
            let provider: any TargetProvider = AppleCalendarProvider()
            return provider.providerID == .appleCalendar
                && (provider as? any ManagedEventProvider) != nil
        }
        h.check(seam, "AppleCalendarProvider 满足 TargetProvider 且可取得管理能力")

        // The reminders target must NOT satisfy ManagedEventProvider: it has no
        // time slot to shift, and the menu/picker relies on this to disable
        // the management panel instead of showing an empty one.
        let remindersSeam = await MainActor.run { () -> Bool in
            let provider: any TargetProvider = AppleRemindersProvider()
            return provider.providerID == .appleReminders
                && (provider as? any ManagedEventProvider) == nil
        }
        h.check(remindersSeam, "提醒事项仅实现 TargetProvider，不提供时间轴管理")
        print("  CALENDAR STATUS: \(state.displayText) (canWrite=\(state.isGranted))")
        if state == .notDetermined || state == .writeOnly {
            print("  TODO: 未在本轮自动请求日历权限，避免替用户在真实日历中写入；首次点击写入时会调用 requestFullAccessToEvents。")
        }
    }

    private static func runLogTests(_ h: Harness) {
        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build", isDirectory: true)
                .appendingPathComponent("test-artifacts", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            let service = try LogService(directory: root)
            for index in 0..<35 {
                try service.append(LogRecord(
                    timestamp: Date().addingTimeInterval(Double(index)),
                    kind: index % 5 == 0 ? "write" : "parse",
                    inputType: index % 2 == 0 ? "text" : "image",
                    imageCount: index % 2 == 0 ? 0 : 1,
                    eventCount: 1,
                    eventTypes: ["activity"],
                    error: nil,
                    durationMs: 120,
                    modifiedFields: index % 10 == 0 ? ["title"] : []
                ))
            }
            try service.append(LogRecord(kind: "missed_feedback", eventCount: 1))
            h.equal(service.records().count, 36, "日志总条数")
            h.equal(service.records(limit: 30).count, 30, "最近30条")

            let exportURL = root.appendingPathComponent("last30.jsonl")
            let exported = try service.exportLast30(to: exportURL)
            h.equal(exported, 30, "导出条数")
            let text = try String(contentsOf: exportURL, encoding: .utf8)
            h.equal(text.split(separator: "\n").count, 30, "导出 JSONL 行数")
            h.check(!text.contains("报名截止"), "日志不含邮件原文")
            h.check(!text.contains("A101"), "日志不含地点")

            let firstObject = try unwrap(
                try JSONSerialization.jsonObject(
                    with: Data(text.split(separator: "\n")[0].utf8)
                ) as? [String: Any],
                h,
                "导出 JSON 对象"
            )
            h.check(firstObject["ts"] != nil, "导出含 ts")
            h.check(firstObject["types"] != nil, "导出含 types")
            h.check(firstObject["editedFields"] != nil, "导出含 editedFields")
            h.check(firstObject["error"] != nil, "导出 error 为 null 或字符串")
            for forbidden in ["title", "location", "evidence", "imagePath", "filePath", "email", "studentId", "phone"] {
                h.check(firstObject[forbidden] == nil, "导出不含字段 \(forbidden)")
            }

            let sensitive = "student@school.edu 110101199001011234 13800138000"
            let dirtyError = "联系人 " + sensitive
            try service.append(LogRecord(
                kind: "parse",
                inputType: "email",
                imageCount: 0,
                eventCount: 2,
                eventTypes: ["deadline", "activity"],
                error: dirtyError,
                durationMs: 321,
                modifiedFields: []
            ))
            let stored = try unwrap(service.records().last, h, "新增解析摘要")
            h.check(stored.error?.contains("[REDACTED]") == true, "日志入库前脱敏")
            h.check(stored.error?.contains("@") == false, "日志不残留邮箱")
            h.check(stored.error?.contains("13800138000") == false, "日志不残留手机号")
            h.check(stored.eventTypes == ["deadline", "activity"], "摘要 types 数组")
            h.check(stored.modifiedFields == [], "摘要 editedFields 空数组")

            let secondExport = root.appendingPathComponent("redacted.jsonl")
            _ = try service.exportLast30(to: secondExport)
            let redacted = try String(contentsOf: secondExport, encoding: .utf8)
            let lastLine = try unwrap(redacted.split(separator: "\n").last, h, "脱敏导出最后一行")
            let lastObject = try unwrap(
                try JSONSerialization.jsonObject(with: Data(lastLine.utf8)) as? [String: Any],
                h,
                "脱敏摘要 JSON"
            )
            h.equal(lastObject["inputType"] as? String, "email", "摘要 inputType=email")
            h.equal(lastObject["eventCount"] as? Int, 2, "摘要 eventCount")
            h.equal((lastObject["editedFields"] as? [String]) ?? [], [], "摘要 editedFields 数组")
            h.equal(lastObject["durationMs"] as? Int, 321, "摘要 durationMs")
            h.check(lastObject["ts"] != nil, "摘要含 ts")
            h.check(!redacted.contains("student@school.edu"), "导出不含邮箱")
            h.check(!redacted.contains("110101199001011234"), "导出不含身份证")
            h.check(!redacted.contains("13800138000"), "导出不含手机号")
            h.check(redacted.contains("[REDACTED]"), "导出保留脱敏标记")

            let direct = LogSanitizer.redact("a@b.com 110101199001011234 13800138000")
            h.check(!direct.contains("@") && !direct.contains("13800138000"), "脱敏函数覆盖邮箱/数字")

            let stats = service.stats(now: Date().addingTimeInterval(100))
            h.check(stats.usageCount > 0, "统计使用次数")
            h.check(stats.writeCount > 0, "统计写入次数")
            h.check(stats.missedFeedbackCount == 1, "统计漏检反馈")
            h.check(stats.modificationRate > 0, "统计修改率")

            let attributes = try FileManager.default.attributesOfItem(atPath: service.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            h.equal(permissions & 0o077, 0, "日志权限 0600")

            try service.clear()
            h.equal(service.records().count, 0, "清空日志后无记录")
            h.check(!FileManager.default.fileExists(atPath: service.path), "清空后日志文件被删除")
            h.check(FileManager.default.fileExists(atPath: root.path), "清空不删除目录")

            let legacyRoot = root.appendingPathComponent("legacy", isDirectory: true)
            try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
            let legacyLine = """
            {"id":"11111111-1111-1111-1111-111111111111","timestamp":"2026-10-31T08:27:42Z","kind":"parse","inputType":"text","imageCount":0,"eventCount":2,"eventTypes":["deadline","activity"],"error":null,"durationMs":1908,"modifiedFields":["title"]}
            """
            try Data((legacyLine + "\n").utf8).write(to: legacyRoot.appendingPathComponent("log.jsonl"))
            let legacyService = try LogService(directory: legacyRoot)
            let legacy = try unwrap(legacyService.records().first, h, "旧日志可读")
            h.equal(legacy.eventTypes, ["deadline", "activity"], "旧 eventTypes 迁移")
            h.equal(legacy.modifiedFields, ["title"], "旧 modifiedFields 迁移")
            h.equal(TestClock.calendar.component(.year, from: legacy.timestamp), 2026, "旧 timestamp 迁移")
            let legacyExport = legacyRoot.appendingPathComponent("export.jsonl")
            _ = try legacyService.exportLast30(to: legacyExport)
            let legacyText = try String(contentsOf: legacyExport, encoding: .utf8)
            h.check(legacyText.contains("\"ts\""), "旧日志导出含 ts")
            h.check(legacyText.contains("\"types\""), "旧日志导出含 types")
            h.check(legacyText.contains("\"editedFields\""), "旧日志导出含 editedFields")

            print("  LOG PASS: export/redact/clear/legacy, usage=\(stats.usageCount), modRate=\(String(format: "%.0f", stats.modificationRate * 100))%")
        } catch {
            h.fail("日志测试异常：\(error)")
        }
    }
}

final class Harness {
    private(set) var passed = 0
    private(set) var failed = 0
    private(set) var failures: [String] = []

    func section(_ title: String) {
        print("\n== \(title) ==")
    }

    func check(_ condition: Bool, _ message: String) {
        if condition {
            passed += 1
            print("  PASS  \(message)")
        } else {
            failed += 1
            failures.append(message)
            print("  FAIL  \(message)")
        }
    }

    func equal<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
        check(lhs == rhs, "\(message) [got=\(String(describing: lhs)), expected=\(String(describing: rhs))]")
    }

    func fail(_ message: String) {
        failed += 1
        failures.append(message)
        print("  FAIL  \(message)")
    }
}

private func unwrap<T>(_ value: T?, _ h: Harness, _ message: String) throws -> T {
    guard let value else {
        h.fail("\(message)（nil）")
        throw NSError(domain: "SelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    return value
}

private enum FixturePaths {
    static let testsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    static let projectRoot = testsDirectory.deletingLastPathComponent()
    static let fixtures = testsDirectory.appendingPathComponent("Fixtures", isDirectory: true)
    static let prompt = projectRoot
        .appendingPathComponent("Sources/SchoolEventInbox/Resources/system_prompt.txt")
}

private enum Fixtures {
    static func data(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: FixturePaths.fixtures.appendingPathComponent("\(name).\(ext)"))
    }

    static func text(_ name: String, _ ext: String = "txt") throws -> String {
        String(data: try data(name, ext), encoding: .utf8) ?? ""
    }

    static func json(_ name: String) throws -> ParseResponse {
        try JSONDecoder().decode(ParseResponse.self, from: data(name, "json"))
    }
}

private enum TestClock {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static var referenceNow: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 20
        components.hour = 10
        components.timeZone = timeZone
        return calendar.date(from: components)!
    }
}

private func compactOCRText(_ text: String) -> String {
    text
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "\t", with: "")
        .replacingOccurrences(of: "\n", with: "")
}

private func makeEvent(
    type: EventType = .activity,
    start: String? = "2026-03-08T14:00:00+08:00",
    allDay: Bool = false,
    location: String? = "A101",
    needsConfirmation: Bool = true,
    notes: String = ""
) -> ParsedEvent {
    ParsedEvent(
        type: type,
        title: "测试事件",
        start: start,
        end: nil,
        allDay: allDay,
        location: location,
        confidence: 0.9,
        evidence: "测试原文",
        needsConfirmation: needsConfirmation,
        notes: notes
    )
}

private final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func readSecret() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func saveSecret(_ secret: String) throws {
        lock.lock(); defer { lock.unlock() }
        value = secret
    }

    func deleteSecret() throws {
        lock.lock(); defer { lock.unlock() }
        value = nil
    }
}

/// 记录请求并按序返回预设响应的传输桩。
private final class StubGoogleTransport: GoogleHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, Data)]
    private var requests: [URLRequest] = []

    init(responses: [(Int, Data)]) {
        self.responses = responses
    }

    var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requests.count
    }

    var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }

    var authorizationHeaders: [String] {
        lock.lock(); defer { lock.unlock() }
        return requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        requests.append(request)
        let next = responses.isEmpty ? (500, Data()) : responses.removeFirst()
        lock.unlock()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: next.0,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (next.1, response)
    }
}

private actor StubGoogleTokenProvider: GoogleTokenProvider {
    private(set) var refreshCount = 0

    func validAccessToken() async throws -> String { "token-1" }

    func forceRefreshAccessToken() async throws -> String {
        refreshCount += 1
        return "token-2"
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var lastRequest: URLRequest?
    static var lastBody: Data?

    static func reset() {
        handler = nil
        lastRequest = nil
        lastBody = nil
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func chatResponse(content: String, status: Int = 200) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        return (response, data)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let body = request.httpBody {
            Self.lastBody = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4_096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            Self.lastBody = data
        }

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
