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
                        Button(L10n.t(model.calendarState == .writeOnly ? "升级为完整访问" : "立即授权", model.calendarState == .writeOnly ? "Upgrade to Full Access" : "Authorize now")) {
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
                        Text(L10n.t("已确认事件会按类型写入独立日历，失败时回退到默认日历", "Confirmed events go to per-type calendars; falls back to the default calendar") + (model.calendarName.isEmpty ? "" : "：" + model.calendarName))
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

                Button {
                    model.writeToCalendar()
                } label: {
                    if model.isWriting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("写入 Apple 日历", systemImage: "calendar.badge.plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canTapWrite)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .help("⌘⇧↩ 写入已确认事件")
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
