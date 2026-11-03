import SchoolEventInboxCore
import SwiftUI

struct FooterBar: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        VStack(spacing: 7) {
            if let prompt = model.calendarPermissionPrompt {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(model.calendarState == .notDetermined ? Color.secondary : Color.red)
                    Text(L10n.dynamic(prompt))
                        .font(.caption)
                        .foregroundStyle(model.calendarState == .notDetermined ? Color.secondary : Color.red)
                    if model.calendarState == .denied || model.calendarState == .restricted {
                        Button("打开系统设置") {
                            model.openCalendarPrivacySettings()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    } else if model.calendarState == .notDetermined || model.calendarState == .writeOnly {
                        Button(model.authorizeButtonTitle) {
                            model.requestCalendarAccess()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if !model.lastWriteSummary.isEmpty {
                        Text(L10n.dynamic(model.lastWriteSummary))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(writeSummaryColor)
                    } else {
                        Text(model.writeTargetHint + (model.calendarName.isEmpty ? "" : "：" + model.calendarName))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if !model.lastWriteDetail.isEmpty {
                        Text(L10n.dynamic(model.lastWriteDetail))
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    Text(statsText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if let exportMessage = model.exportMessage {
                    Text(L10n.dynamic(exportMessage))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 260, alignment: .trailing)
                }

                Button(role: .destructive) {
                    model.requestClearLogs()
                } label: {
                    Label("清空日志", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("清空本地 JSONL 日志，不会删除其他文件")

                Button {
                    model.exportLogs()
                } label: {
                    Label("导出最近 30 条", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("导出脱敏后的本地 JSONL 日志，不包含邮件原文、标题、地点或敏感字段")

                // Write target picker. Segmented and compact so it reads as
                // part of the write action rather than as a new settings area.
                Picker("", selection: Binding(
                    get: { model.writeTarget },
                    set: { model.selectTarget($0) }
                )) {
                    ForEach(WriteTarget.allCases) { target in
                        Text(target.shortTitle).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.regular)
                .frame(width: 210)
                .help(L10n.t("选择写入 Apple 日历或 Apple 提醒事项", "Choose whether to write to Apple Calendar or Apple Reminders"))

                // Google 目标需要用户指定写入哪个日历（与 Apple 侧"按类型自动分日历"不同）。
                if model.writeTarget == .googleCalendar, !model.googleCalendars.isEmpty {
                    Menu {
                        ForEach(model.googleCalendars, id: \.id) { entry in
                            Button {
                                model.selectGoogleCalendar(entry)
                            } label: {
                                if entry.id == model.selectedGoogleCalendarID {
                                    Label(entry.summary, systemImage: "checkmark")
                                } else {
                                    Text(entry.summary)
                                }
                            }
                        }
                    } label: {
                        Label(
                            model.selectedGoogleCalendarName.isEmpty
                                ? L10n.t("选择日历", "Choose calendar")
                                : model.selectedGoogleCalendarName,
                            systemImage: "calendar"
                        )
                        .lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 190)
                    .help(L10n.t("选择写入哪个 Google 日历", "Choose which Google calendar to write to"))
                }

                Button {
                    model.writeToCalendar()
                } label: {
                    if model.isWriting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(model.writeActionTitle, systemImage: model.writeActionSymbol)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canTapWrite)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .help(L10n.t("⌘⇧↩ 写入已确认事件", "⌘⇧↩ Write confirmed events"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var writeSummaryColor: Color {
        if model.unresolvedConflictCount > 0 { return .orange }
        if model.lastWriteSummary.contains("未写入") { return .orange }
        return .primary
    }

    private var statsText: String {
        let rate = Int((model.logStats.modificationRate * 100).rounded())
        if language.isEnglish {
            return "Last \(model.logStats.windowDays) days: \(model.logStats.usageCount) uses · \(rate)% edited · \(model.logStats.missedFeedbackCount) missed"
        }
        return "近 \(model.logStats.windowDays) 天：使用 \(model.logStats.usageCount) 次 · 修改率 \(rate)% · 漏检反馈 \(model.logStats.missedFeedbackCount) 次"
    }
}
