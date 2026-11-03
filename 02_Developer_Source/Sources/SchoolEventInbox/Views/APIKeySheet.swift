import SchoolEventInboxCore
import SwiftUI

struct APIKeySheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var statusText: String {
        switch model.apiKeyPresence {
        case .present: return "Keychain 已保存"
        case .inaccessible: return "存在但不可读"
        case .missing: return model.apiKeyConfigured ? "已配置" : "未配置"
        }
    }

    private var statusColor: Color {
        switch model.apiKeyPresence {
        case .present: return .green
        case .inaccessible: return .orange
        case .missing: return model.apiKeyConfigured ? .green : .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("DeepSeek API Key", systemImage: "key.fill")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(L10n.t(model.apiKeyConfigured ? "已配置" : "未配置", model.apiKeyConfigured ? "Configured" : "Not configured"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.apiKeyConfigured ? .green : .orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (model.apiKeyConfigured ? Color.green : Color.orange).opacity(0.1),
                        in: Capsule()
                    )
            }

            Text(L10n.t("Key 只保存在本机 macOS Keychain（service: \(KeychainService.service)），不会写入代码库、日志或导出文件。", "The key is stored only in the macOS Keychain (service: \(KeychainService.service)) and is not written to source, logs or exports."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.apiKeyPresence == .present {
                Label("Keychain 中已保存一个 Key；出于安全不回显。重新输入会覆盖它。", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.apiKeyPresence == .inaccessible {
                Label("检测到 Keychain 条目，但当前构建无权读取。重新保存一次，必要时在系统提示中选择 Always Allow。", systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            SecureField("sk-…", text: $model.apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            if let message = model.apiKeyMessage {
                Label(L10n.dynamic(message), systemImage: model.apiKeyIsError ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(model.apiKeyIsError ? Color.red : Color.green)
            }

            HStack {
                Button("删除已存 Key", role: .destructive) {
                    model.deleteAPIKey()
                }
                .disabled(!model.apiKeyConfigured)

                Spacer()

                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存到 Keychain") {
                    model.saveAPIKey()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}
