import SchoolEventInboxCore
import SwiftUI

struct EventListPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorMessage = model.errorMessage {
                BannerView(
                    text: errorMessage,
                    icon: "exclamationmark.octagon.fill",
                    tint: .red
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            if let notice = model.notice {
                BannerView(
                    text: notice,
                    icon: "info.circle.fill",
                    tint: .orange
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            if model.drafts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach($model.drafts) { $draft in
                            EventCard(
                                draft: $draft,
                                onTimingChanged: {
                                    model.clearConflict(for: draft.id)
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("待确认事件")
                .font(.title2.weight(.semibold))
            if !model.drafts.isEmpty {
                Text("\(model.drafts.count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()

            if model.unresolvedConflictCount > 0 {
                Label(L10n.t("\(model.unresolvedConflictCount) 条冲突", "\(model.unresolvedConflictCount) conflicts"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }

            Button {
                model.flagMissedEvent()
            } label: {
                Label(L10n.t(model.missedFeedbackSent ? "已反馈漏检" : "漏检反馈", model.missedFeedbackSent ? "Missed event reported" : "Report missed event"), systemImage: "flag")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!model.parseSucceeded || model.missedFeedbackSent)
            .help("记录一次“有事件未被识别”。只记录匿名计数，不保存原文。")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("还没有待确认事件")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("在左侧粘贴邮件正文或截图，点击“解析”。\n每条事件都必须经过你核对确认。")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BannerView: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(L10n.dynamic(text))
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.22)))
    }
}
