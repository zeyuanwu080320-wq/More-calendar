import Foundation

/// Google Calendar 目标。
///
/// 写入模型（与 Apple 侧不同，已与用户确认）：
/// - 用户选定**一个**日历作为目标，用事件的 `colorId` 区分类型，因此不需要
///   创建 secondary calendar，也不需要全量 `calendar` scope。
/// - 托管标记同时写进 `description` 与 `extendedProperties.private`：
///   前者是人类可读的兼容标记，后者用于精确筛选（用户改了备注也不会丢）。
@MainActor
public final class GoogleCalendarProvider: ManagedEventProvider {
    /// 已选日历的 UserDefaults key。
    public static let selectedCalendarDefaultsKey = "SchoolEventInbox.googleCalendarID"

    public private(set) var routingNotice: String?
    public var titleLanguage: ManagedCalendarLanguage = .chinese

    private let transport: any GoogleHTTPTransport
    private var oauthManager: GoogleOAuthManager?
    private var apiClient: GoogleAPIClient?

    /// `authorizationState` 是同步属性，所以这里缓存最近一次已知状态。
    private var authorized = false
    private var selectedCalendar: GoogleCalendarListEntry?

    public init(transport: any GoogleHTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    // MARK: - TargetProvider

    public var providerID: TargetProviderID { .googleCalendar }

    public var displayName: String { "Google 日历" }

    public var authorizationState: CalendarAccessState {
        authorized ? .fullAccess : .notDetermined
    }

    public var targetName: String? { selectedCalendar?.summary }

    public func resetRoutingNotice() {
        routingNotice = nil
    }

    /// 读 Keychain 判断是否已连接。**不要在启动时自动调用**：Keychain 可能弹窗。
    public func refreshAuthorizationState() async {
        guard let manager = try? makeManager() else {
            authorized = false
            return
        }
        authorized = await manager.hasStoredRefreshToken()
        if authorized {
            await loadSelectedCalendarIfNeeded()
        }
    }

    @discardableResult
    public func requestAccess() async throws -> Bool {
        do {
            let manager = try makeManager()
            _ = try await manager.authorize()
            authorized = true
            await loadSelectedCalendarIfNeeded(forceList: true)
            return true
        } catch {
            authorized = false
            throw targetError(error)
        }
    }

    /// 断开连接：清掉 Keychain 里的 refresh_token 与内存缓存。
    public func signOut() async {
        if let manager = try? makeManager() {
            await manager.signOut()
        }
        authorized = false
        selectedCalendar = nil
    }

    public func findConflicts(for draft: EventDraft) async throws -> [CalendarConflict] {
        guard draft.hasStart else { return [] }
        do {
            let interval = draft.calendarInterval()
            let events = try await listEvents(
                calendarID: try selectedCalendarID(),
                timeMin: interval.start,
                timeMax: interval.end
            )
            let name = targetName ?? "Google 日历"
            return events
                .compactMap { GoogleCalendarMapper.conflict(from: $0, calendarName: name) }
                .filter { ConflictDetector.overlaps(interval, DateInterval(start: $0.start, end: $0.end)) }
                .sorted { $0.start < $1.start }
        } catch {
            throw targetError(error)
        }
    }

    public func saveEvents(_ drafts: [EventDraft]) async throws {
        guard authorizationState.canAttemptWrite else { throw TargetProviderError.accessDenied }
        do {
            let api = try api()
            let calendarID = try selectedCalendarID()
            for draft in drafts {
                let body = GoogleCalendarMapper.makeEventBody(from: draft)
                let request = try GoogleAPIRequest.json(
                    "POST",
                    path: "/calendars/\(escape(calendarID))/events",
                    body: body
                )
                _ = try await api.send(request, as: GoogleEvent.self)
            }
        } catch {
            throw targetError(error)
        }
    }

    // MARK: - ManagedEventProvider

    public func fetchManagedEvents() async throws -> [ManagedEvent] {
        do {
            let calendarID = try selectedCalendarID()
            let now = Date()
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let end = calendar.date(byAdding: .year, value: 1, to: now) ?? now
            let events = try await listEvents(
                calendarID: calendarID,
                timeMin: start,
                timeMax: end,
                managedOnly: true
            )
            let name = targetName ?? "Google 日历"
            return events
                .compactMap {
                    GoogleCalendarMapper.managedEvent(
                        from: $0,
                        calendarID: calendarID,
                        calendarName: name
                    )
                }
                .sorted { $0.start < $1.start }
        } catch {
            throw targetError(error)
        }
    }

    @discardableResult
    public func deleteManagedEvent(id: String) async throws -> Int {
        guard let parts = GoogleCalendarMapper.splitManagedEventID(id) else {
            throw TargetProviderError.eventNotFound
        }
        do {
            let request = GoogleAPIRequest(
                method: "DELETE",
                path: "/calendars/\(escape(parts.calendarID))/events/\(escape(parts.eventID))"
            )
            try await api().send(request)
            return 1
        } catch GoogleAPIError.notFound {
            throw TargetProviderError.eventNotFound
        } catch {
            throw targetError(error)
        }
    }

    public func deleteManagedEvents(ids: [String]) async throws -> ManagedDeleteResult {
        var deleted = 0
        var failed = 0
        for id in ids {
            do {
                deleted += try await deleteManagedEvent(id: id)
            } catch {
                failed += 1
            }
        }
        return ManagedDeleteResult(deleted: deleted, failed: failed)
    }

    @discardableResult
    public func deleteAllManagedEvents() async throws -> Int {
        let events = try await fetchManagedEvents()
        var removed = 0
        for event in events {
            do {
                removed += try await deleteManagedEvent(id: event.id)
            } catch {
                // 继续删剩下的，让调用方拿到部分结果。
            }
        }
        return removed
    }

    /// 批量平移。
    ///
    /// Google 侧不做写入前的冲突预检（那需要额外拉取整段区间并与所有事件比对），
    /// 因此 `conflicts` 恒为 0；事件时间重叠由 Google 自己接受。
    public func shiftManagedEvents(ids: [String], by interval: TimeInterval) async throws -> ManagedShiftResult {
        guard !ids.isEmpty, interval != 0 else {
            return ManagedShiftResult(shifted: 0, conflicts: 0, failed: 0)
        }
        var shifted = 0
        var failed = 0
        do {
            let api = try api()
            for id in ids {
                guard let parts = GoogleCalendarMapper.splitManagedEventID(id) else {
                    failed += 1
                    continue
                }
                do {
                    let path = "/calendars/\(escape(parts.calendarID))/events/\(escape(parts.eventID))"
                    let current = try await api.send(GoogleAPIRequest(path: path), as: GoogleEvent.self)
                    guard let body = GoogleCalendarMapper.shiftedBody(from: current, by: interval),
                          let data = try? JSONEncoder().encode(body) else {
                        failed += 1
                        continue
                    }
                    let patch = GoogleAPIRequest(
                        method: "PATCH",
                        path: path,
                        body: data,
                        contentType: "application/json; charset=utf-8"
                    )
                    _ = try await api.send(patch, as: GoogleEvent.self)
                    shifted += 1
                } catch {
                    failed += 1
                }
            }
        } catch {
            throw targetError(error)
        }
        return ManagedShiftResult(shifted: shifted, conflicts: 0, failed: failed)
    }

    /// Google 侧不创建、也不拥有日历（用户选定已有日历），因此没有可改名的容器。
    public func syncLocalizedTitles(to language: ManagedCalendarLanguage) async -> Int {
        titleLanguage = language
        return 0
    }

    // MARK: - 日历选择（UI 用）

    /// 列出可写日历，供 UI 让用户选择写入目标。
    public func listCalendars() async throws -> [GoogleCalendarListEntry] {
        do {
            let api = try api()
            let items = try await api.sendAllPages(
                GoogleAPIRequest(path: "/users/me/calendarList"),
                as: GoogleCalendarListResponse.self,
                items: { $0.items ?? [] },
                nextToken: { $0.nextPageToken }
            )
            return items
                .filter { $0.isWritable }
                .sorted { ($0.primary == true ? 0 : 1, $0.summary) < ($1.primary == true ? 0 : 1, $1.summary) }
        } catch {
            throw targetError(error)
        }
    }

    public func selectCalendar(_ entry: GoogleCalendarListEntry) {
        selectedCalendar = entry
        UserDefaults.standard.set(entry.id, forKey: Self.selectedCalendarDefaultsKey)
    }

    /// 载入已保存的日历；没有就用 primary。
    public func loadSelectedCalendarIfNeeded(forceList: Bool = false) async {
        guard forceList || selectedCalendar == nil else { return }
        guard authorized else { return }
        do {
            let calendars = try await listCalendars()
            let storedID = UserDefaults.standard.string(forKey: Self.selectedCalendarDefaultsKey)
            let selected = calendars.first { $0.id == storedID }
                ?? calendars.first { $0.primary == true }
                ?? calendars.first
            selectedCalendar = selected
            if let selected {
                UserDefaults.standard.set(selected.id, forKey: Self.selectedCalendarDefaultsKey)
            }
        } catch {
            routingNotice = "无法读取 Google 日历列表：\(error.localizedDescription)"
        }
    }

    // MARK: - 内部

    private func makeManager() throws -> GoogleOAuthManager {
        if let oauthManager { return oauthManager }
        let client: GoogleOAuthClient
        do {
            client = try GoogleOAuthClientLoader.load()
        } catch {
            throw TargetProviderError.providerUnavailable(error.localizedDescription)
        }
        let manager = GoogleOAuthManager(client: client, transport: transport)
        oauthManager = manager
        return manager
    }

    private func api() throws -> GoogleAPIClient {
        if let apiClient { return apiClient }
        let manager = try makeManager()
        let client = GoogleAPIClient(transport: transport, tokenProvider: manager)
        apiClient = client
        return client
    }

    private func selectedCalendarID() throws -> String {
        if let id = selectedCalendar?.id { return id }
        if let stored = UserDefaults.standard.string(forKey: Self.selectedCalendarDefaultsKey), !stored.isEmpty {
            return stored
        }
        return "primary"
    }

    private func listEvents(
        calendarID: String,
        timeMin: Date,
        timeMax: Date,
        managedOnly: Bool = false
    ) async throws -> [GoogleEvent] {
        let api = try api()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var query: [URLQueryItem] = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: timeMin)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: timeMax)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "maxResults", value: "250")
        ]
        if managedOnly {
            query.append(URLQueryItem(
                name: "privateExtendedProperty",
                value: "\(GoogleCalendarMapper.managedPropertyKey)=1"
            ))
        }
        let request = GoogleAPIRequest(
            path: "/calendars/\(escape(calendarID))/events",
            query: query
        )
        let items = try await api.sendAllPages(
            request,
            as: GoogleEventsListResponse.self,
            items: { $0.items ?? [] },
            nextToken: { $0.nextPageToken }
        )
        return items.filter { $0.status != "cancelled" }
    }

    /// Google 的日历 id 常含 `@`（如 `family@group.calendar.google.com`），必须转义。
    private func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "@:/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// 把底层错误收敛成 `TargetProviderError`，避免 UI 出现第三种错误类型。
    private func targetError(_ error: Error) -> Error {
        if let error = error as? TargetProviderError { return error }
        if let error = error as? GoogleAPIError {
            if case .unauthorized = error { return TargetProviderError.accessDenied }
            return TargetProviderError.providerUnavailable(error.localizedDescription)
        }
        if let error = error as? GoogleOAuthError {
            if case .notAuthorized = error { return TargetProviderError.accessDenied }
            return TargetProviderError.providerUnavailable(error.localizedDescription)
        }
        return TargetProviderError.saveFailed(error.localizedDescription)
    }
}
