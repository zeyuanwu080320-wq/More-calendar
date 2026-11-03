import AppKit
import SchoolEventInboxCore
import SwiftUI

struct ManagedEventsView: View {
    /// The panel only needs the management capabilities, not the whole
    /// provider surface.
    let provider: any ManagedEventProvider
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageManager

    @State private var events: [ManagedEvent] = []
    @State private var selected = Set<String>()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showClearConfirmation = false
    @State private var showDeleteSelectedConfirmation = false
    @State private var showShiftSheet = false
    @State private var shiftConflicts: [ManagedShiftConflict] = []
    @State private var showShiftConflicts = false
    @State private var pendingRecurringDelete: ManagedEvent?
    @State private var showRecurringDeleteAlert = false
    @State private var permissionState: CalendarAccessState = .unknown
    @State private var customHours = 0
    @State private var customMinutes = 0

    private var selectedEvents: [ManagedEvent] {
        events.filter { selected.contains($0.id) }
    }

    private var selectedHasRecurring: Bool {
        selectedEvents.contains(where: \.isRecurring)
    }

    private var deleteSelectedMessage: String {
        var text = "这将同时从 Apple 日历中移除它们。"
        let recurring = selectedEvents.filter(\.isRecurring).count
        if recurring > 0 {
            text += "\n其中 \(recurring) 条为循环事件，将删除其未来的所有发生记录。"
        }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorMessage {
                banner(L10n.dynamic(errorMessage), color: .red)
            }
            if let statusMessage {
                banner(L10n.dynamic(statusMessage), color: .green)
            }

            if permissionState != .fullAccess {
                permissionStateView
            } else if isLoading && events.isEmpty {
                ProgressView(L10n.t("正在读取日历…", "Loading calendar…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                emptyState
            } else {
                list
            }

            Divider()
            footer
        }
        .frame(width: 760, height: 620)
        .onAppear { Task { await refresh() } }
        .sheet(isPresented: $showShiftSheet) {
            shiftSheet
                .environmentObject(language)
        }
        .sheet(isPresented: $showShiftConflicts) {
            shiftConflictSheet
                .environmentObject(language)
        }
        .alert(L10n.t("清空所有本工具创建的事件？", "Clear all app-created events?"), isPresented: $showClearConfirmation) {
            Button(L10n.t("清空全部", "Clear all"), role: .destructive) { Task { await clearAll() } }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("只会删除带有管理标签的事件；循环事件会删除未来的发生记录。", "Only tagged events are deleted; recurring events remove future occurrences."))
        }
        .alert(
            L10n.t("确认删除选中的 \(selected.count) 个事件吗？",
                   "Delete the \(selected.count) selected events?"),
            isPresented: $showDeleteSelectedConfirmation
        ) {
            Button(L10n.t("删除选中", "Delete Selected"), role: .destructive) { Task { await deleteSelected() } }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.dynamic(deleteSelectedMessage))
        }
        .alert(L10n.t("删除循环事件？", "Delete recurring event?"), isPresented: $showRecurringDeleteAlert) {
            Button(L10n.t("删除未来所有发生", "Delete all future occurrences"), role: .destructive) {
                if let event = pendingRecurringDelete { Task { await delete(event) } }
                pendingRecurringDelete = nil
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) { pendingRecurringDelete = nil }
        } message: {
            Text(L10n.t("这是一个循环事件，删除将移除其所有未来的发生记录。", "This is a recurring event. Deleting it removes all future occurrences."))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(L10n.t("管理事件", "Managed Events"), systemImage: "calendar.badge.gearshape")
                .font(.title2.weight(.semibold))
            Text(L10n.t("仅显示本工具创建的事件", "App-created events only"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                Label(L10n.t("刷新", "Refresh"), systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
            Button(L10n.t("关闭", "Close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var permissionStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(L10n.t("需要完整权限才能管理", "Full access is required to manage events"))
                .font(.headline)
            Text(L10n.t("本页面只读取带有管理标签的事件，不会展示你手动添加的私人事件。", "This page only reads tagged events; private events you added manually are never shown."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                if permissionState == .notDetermined || permissionState == .writeOnly {
                    Button(L10n.t("请求完整访问", "Request Full Access")) { requestAccess() }
                        .buttonStyle(.borderedProminent)
                }
                if permissionState == .denied || permissionState == .restricted {
                    Button(L10n.t("打开系统设置", "Open System Settings")) { openSettings() }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.t("暂无由本工具创建的事件", "No events created by this tool"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(L10n.t("通过主界面写入事件，并确认其备注包含管理标签后，会出现在这里。", "Events written from the main window with the management tag appear here."))
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(events) { event in
                    row(event)
                }
            }
            .padding(12)
        }
    }

    private func row(_ event: ManagedEvent) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selected.contains(event.id) },
                set: { isOn in
                    if isOn { selected.insert(event.id) } else { selected.remove(event.id) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Image(systemName: (event.type ?? .other).symbolName)
                .foregroundStyle(typeColor(event.type ?? .other))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if event.isRecurring {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Text(timeText(event))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(event.calendarName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(L10n.typeName(event.type ?? .other))
                        .font(.caption2)
                        .foregroundStyle(typeColor(event.type ?? .other))
                }
            }

            Spacer()

            Button(role: .destructive) {
                if event.isRecurring {
                    pendingRecurringDelete = event
                    showRecurringDeleteAlert = true
                } else {
                    Task { await delete(event) }
                }
            } label: {
                Label(L10n.t("删除", "Delete"), systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(L10n.t("删除此事件", "Delete this event"))
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(L10n.t("全选", "Select all")) { selected = Set(events.map(\.id)) }
                .disabled(events.isEmpty)
            Button(L10n.t("取消全选", "Deselect all")) { selected.removeAll() }
                .disabled(selected.isEmpty)
            Text(L10n.t("\(selected.count) 条已选择", "\(selected.count) selected"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Deliberately low-emphasis: "clear all" is destructive and rare,
            // so it reads as a secondary text action next to the two primary
            // ones (delete selected / batch shift).
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label(L10n.t("清空所有", "Clear all"), systemImage: "trash")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(events.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            .disabled(events.isEmpty)
            .help(L10n.t("删除本工具创建的全部事件", "Delete every event created by this app"))

            Button(role: .destructive) {
                showDeleteSelectedConfirmation = true
            } label: {
                Label(L10n.t("删除选中", "Delete Selected"), systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(selected.isEmpty)
            .help(L10n.t("只删除当前勾选的事件", "Delete only the checked events"))

            Button {
                if selectedHasRecurring {
                    statusMessage = "循环事件不支持批量平移，请单条修改"
                    errorMessage = nil
                    return
                }
                showShiftSheet = true
            } label: {
                Label(L10n.t("批量平移", "Batch shift"), systemImage: "calendar.badge.clock")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
        .padding(12)
    }

    private var shiftSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t("批量平移", "Batch shift"), systemImage: "calendar.badge.clock")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(L10n.t("\(selected.count) 条已选择", "\(selected.count) selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if selectedHasRecurring {
                Label(L10n.t("循环事件不支持批量平移，请单条修改", "Recurring events cannot be batch-shifted. Edit them individually."), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(L10n.t("快捷平移", "Quick shift"))
                .font(.headline)
            HStack {
                quickShiftButton(L10n.t("+1 小时", "+1 hour"), seconds: 3_600)
                quickShiftButton(L10n.t("-1 小时", "-1 hour"), seconds: -3_600)
                quickShiftButton(L10n.t("+1 天", "+1 day"), seconds: 86_400)
                quickShiftButton(L10n.t("-1 天", "-1 day"), seconds: -86_400)
                quickShiftButton(L10n.t("+1 周", "+1 week"), seconds: 604_800)
            }
            Divider()
            Text(L10n.t("自定义平移", "Custom shift"))
                .font(.headline)
            HStack {
                TextField(L10n.t("小时", "hours"), value: $customHours, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text(L10n.t("小时", "hours"))
                TextField(L10n.t("分钟", "minutes"), value: $customMinutes, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text(L10n.t("分钟", "minutes"))
                Spacer()
                Button(L10n.t("应用", "Apply")) {
                    let interval = TimeInterval(customHours * 3_600 + customMinutes * 60)
                    Task { await applyShift(interval) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || selectedHasRecurring || (customHours == 0 && customMinutes == 0))
            }
            if let statusMessage {
                Text(L10n.dynamic(statusMessage))
                    .font(.caption)
                    .foregroundStyle(statusMessage.contains("成功") || statusMessage.contains("Shifted") ? .green : .orange)
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 520, height: 340)
    }

    /// Shown after a batch shift that skipped events, naming both sides of each
    /// clash so the user never has to guess what "1 failed" meant.
    private var shiftConflictSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.t("平移冲突详情", "Batch shift conflicts"),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
            Text(L10n.t("以下事件因平移后与已有事件时间重叠，已跳过：",
                        "These events were skipped because the new time overlaps an existing event:"))
                .font(.callout)
                .foregroundStyle(.secondary)
            List(shiftConflicts) { conflict in
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.t("「\(conflict.shiftedTitle)」平移后与「\(conflict.blockingTitle)」发生时间重叠，已跳过。",
                                "“\(conflict.shiftedTitle)” was skipped: its new time overlaps “\(conflict.blockingTitle)”."))
                        .font(.callout)
                    Text(L10n.t("目标时间：\(timeText(conflict.newStart))　·　冲突事件开始：\(timeText(conflict.blockingStart))",
                                "New time: \(timeText(conflict.newStart))　·　Conflicting event starts: \(timeText(conflict.blockingStart))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 200)
            HStack {
                Spacer()
                Button(L10n.t("关闭", "Close")) { showShiftConflicts = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 580, height: 400)
    }

    private func quickShiftButton(_ title: String, seconds: TimeInterval) -> some View {
        Button(title) { Task { await applyShift(seconds) } }
            .disabled(selected.isEmpty || selectedHasRecurring)
    }

    private func refresh() async {
        permissionState = provider.authorizationState
        guard permissionState == .fullAccess else {
            events = []
            selected.removeAll()
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            events = try await provider.fetchManagedEvents()
            selected = selected.intersection(Set(events.map(\.id)))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func requestAccess() {
        Task {
            do {
                _ = try await provider.requestAccess()
            } catch {
                errorMessage = error.localizedDescription
            }
            await refresh()
        }
    }

    /// Deletes exactly the checked events and leaves everything else alone.
    private func deleteSelected() async {
        guard !selected.isEmpty else { return }
        let ids = selected.sorted()
        do {
            let result = try await provider.deleteManagedEvents(ids: ids)
            selected.removeAll()
            statusMessage = result.failed == 0
                ? "已删除 \(result.deleted) 条事件"
                : "已删除 \(result.deleted) 条，\(result.failed) 条失败"
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ event: ManagedEvent) async {
        do {
            try await provider.deleteManagedEvent(id: event.id)
            selected.remove(event.id)
            events.removeAll { $0.id == event.id }
            statusMessage = "已删除 1 条事件"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAll() async {        do {
            let count = try await provider.deleteAllManagedEvents()
            events = []
            selected.removeAll()
            statusMessage = "已删除 \(count) 条事件"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyShift(_ interval: TimeInterval) async {
        guard !selected.isEmpty else { return }
        guard !selectedHasRecurring else {
            statusMessage = "循环事件不支持批量平移，请单条修改"
            return
        }
        guard interval != 0 else { return }
        do {
            let result = try await provider.shiftManagedEvents(ids: Array(selected), by: interval)
            statusMessage = "成功平移 \(result.shifted) 条，\(result.conflicts) 条因冲突失败"
            if result.failed > 0 {
                statusMessage = (statusMessage ?? "") + "，\(result.failed) 条失败"
            }
            // Never fail silently: name every skipped event and what blocked it.
            if !result.conflictDetails.isEmpty {
                shiftConflicts = result.conflictDetails
                showShiftConflicts = true
            }
            await refresh()
            showShiftSheet = false
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func timeText(_ date: Date, allDay: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = allDay ? .none : .short
        return formatter.string(from: date)
    }

    private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func banner(_ text: String, color: Color) -> some View {
        HStack {
            Text(text)
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(color.opacity(0.08))
        .foregroundStyle(color)
    }

    private func timeText(_ event: ManagedEvent) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = event.isAllDay ? .none : .short
        return formatter.string(from: event.start)
    }

    private func typeColor(_ type: EventType) -> Color {
        switch type {
        case .deadline: return .orange
        case .appointment: return .blue
        case .exam: return .red
        case .birthday: return .pink
        case .activity: return .accentColor
        case .other: return .secondary
        }
    }
}
