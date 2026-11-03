import SchoolEventInboxCore
import SwiftUI

struct EventCard: View {
    @Binding var draft: EventDraft
    let onTimingChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            topRow

            if draft.type == .birthday {
                Label(L10n.t("🎂 生日（将设为每年重复）", "🎂 Birthday (repeats yearly)"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.pink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.pink.opacity(0.1), in: Capsule())
            }

            if !draft.validationMessages.isEmpty {
                Label(L10n.dynamic(draft.validationMessages.joined(separator: " · ")), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            timingRows
            locationRow

            evidenceBox
            notesRow
            confidenceRow

            if !draft.conflicts.isEmpty {
                conflictBox
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: draft.isWritten ? 1 : 1.2)
        )
        .opacity(draft.isWritten ? 0.76 : 1)
        .disabled(draft.isWritten)
        .onChange(of: draft.hasStart) { _, _ in onTimingChanged() }
        .onChange(of: draft.start) { _, _ in onTimingChanged() }
        .onChange(of: draft.hasEnd) { _, _ in onTimingChanged() }
        .onChange(of: draft.end) { _, _ in onTimingChanged() }
        .onChange(of: draft.allDay) { _, _ in onTimingChanged() }
    }

    private var borderColor: Color {
        if draft.isWritten { return .green.opacity(0.45) }
        if !draft.conflicts.isEmpty { return .orange.opacity(0.7) }
        if draft.isCritical { return .accentColor.opacity(0.32) }
        return Color.secondary.opacity(0.2)
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 8) {
            typeMenu

            TextField("事件标题", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.headline)
                .disabled(draft.isWritten)

            if draft.isWritten {
                Label("已写入", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Toggle(isOn: $draft.confirmed) {
                Text(L10n.t(draft.isCritical ? "已确认（关键类型锁定）" : "确认写入", draft.isCritical ? "Confirmed (critical type locked)" : "Confirm write"))
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .disabled(draft.isCritical)
            .help(draft.isCritical ? "deadline / appointment / exam 必须确认且不可取消" : "第一版所有事件都需用户确认")
        }
    }

    private var typeMenu: some View {
        Menu {
            ForEach(EventType.allCases, id: \.self) { type in
                Button {
                    applyType(type)
                } label: {
                    Label(L10n.typeName(type), systemImage: type.symbolName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: draft.type.symbolName)
                    .foregroundStyle(typeColor)
                Text(L10n.typeName(draft.type))
                    .foregroundStyle(typeColor)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(typeColor)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(typeColor)
            .background(typeColor.opacity(0.12), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var typeColor: Color {
        switch draft.type {
        case .deadline: return .orange
        case .appointment: return .blue
        case .exam: return .red
        case .birthday: return .pink
        case .activity: return .accentColor
        case .other: return .secondary
        }
    }

    private func applyType(_ type: EventType) {
        draft.type = type
        if type.requiresConfirmation {
            draft.confirmed = true
        }
        if type == .birthday {
            draft.allDay = true
            draft.hasEnd = false
            draft.start = Calendar.current.startOfDay(for: draft.start)
        }
        onTimingChanged()
    }

    private var timingRows: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Label("开始", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .leading)

                if draft.hasStart {
                    if draft.allDay {
                        DatePicker("开始", selection: $draft.start, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .frame(maxWidth: 230, alignment: .leading)
                            .id("start-all-day")
                    } else {
                        DatePicker("开始", selection: $draft.start, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .frame(maxWidth: 230, alignment: .leading)
                            .id("start-timed")
                    }
                } else {
                    Text("需人工补充")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                    Button("补充开始时间") {
                        draft.hasStart = true
                        if !draft.allDay {
                            draft.start = nextHour()
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }

                Spacer()

                Toggle("全天", isOn: $draft.allDay)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .disabled(draft.type == .birthday)
            }

            if draft.type != .birthday {
                HStack(spacing: 8) {
                    Label("结束", systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .leading)

                    if draft.hasEnd {
                        if draft.allDay {
                            DatePicker("结束", selection: $draft.end, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .frame(maxWidth: 230, alignment: .leading)
                                .id("end-all-day")
                        } else {
                            DatePicker("结束", selection: $draft.end, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .frame(maxWidth: 230, alignment: .leading)
                                .id("end-timed")
                        }
                    } else {
                        Text(L10n.t(draft.allDay ? "默认与开始同一天" : "未提供，写入时按开始 +1 小时占位", draft.allDay ? "Same day as start by default" : "Not provided; a 1-hour placeholder is used on write"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Button("补充结束时间") {
                            draft.hasEnd = true
                            draft.end = draft.allDay ? draft.start : draft.start.addingTimeInterval(3_600)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }

                    Spacer()

                    if draft.end <= draft.start && draft.hasEnd && !draft.allDay {
                        Text("结束早于开始")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var locationRow: some View {
        HStack(spacing: 8) {
            Label("地点", systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            TextField("原文未提及时留空，不自行编造", text: $draft.location)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
        }
    }

    private var evidenceBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("原文依据 evidence", systemImage: "quote.opening")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(draft.evidence.isEmpty ? L10n.t("（模型未提供原文片段，请重点核对）", "No evidence supplied; review carefully") : draft.evidence)
                .font(.caption)
                .foregroundStyle(draft.evidence.isEmpty ? Color.red : Color.primary)
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
    }

    private var notesRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Label("歧义说明", systemImage: "text.bubble")
                .font(.caption)
                .foregroundStyle(draft.notes.isEmpty ? Color.secondary : Color.orange)
                .frame(width: 84, alignment: .leading)
            TextField("notes：歧义、缺失字段或重复规则", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.caption)
                .lineLimit(1...3)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(draft.notes.isEmpty ? Color.clear : Color.orange.opacity(0.07))
                )
        }
    }

    private var confidenceRow: some View {
        HStack(spacing: 8) {
            Text("置信度")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ProgressView(value: draft.confidence)
                .frame(width: 90)
                .tint(confidenceColor)
            Text("\(Int((draft.confidence * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(confidenceColor)
            Spacer()
            if draft.needsConfirmationText {
                Text("需人工确认")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var confidenceColor: Color {
        if draft.confidence >= 0.8 { return .green }
        if draft.confidence >= 0.5 { return .orange }
        return .red
    }

    private var conflictBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.t("同一时间段已有 \(draft.conflicts.count) 条日历事件", "\(draft.conflicts.count) calendar events already exist in this time range"), systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            ForEach(draft.conflicts.prefix(5)) { conflict in
                Text("\(Self.timeText(conflict.start))–\(Self.timeText(conflict.end))  \(conflict.title)  ·  \(conflict.calendarName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Toggle("冲突仍写入（不会自动合并或覆盖）", isOn: $draft.writeAnyway)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.orange.opacity(0.28)))
    }

    private func nextHour() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: Date())
        let base = calendar.date(from: components) ?? Date()
        return calendar.date(byAdding: .hour, value: 1, to: base) ?? Date().addingTimeInterval(3_600)
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

private extension EventDraft {
    var needsConfirmationText: Bool {
        true
    }
}
