import SchoolEventInboxCore
import SwiftUI
import UniformTypeIdentifiers

struct InputPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("输入")
                    .font(.title2.weight(.semibold))
                Spacer()
                StatusPill(status: model.workStatus)
            }

            Picker("", selection: Binding(
                get: { model.inputSource },
                set: { model.selectInputSource($0) }
            )) {
                ForEach(InputSource.allCases) { source in
                    Text(source.paneTitle).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help(L10n.t("选择「邮件/截图」或「纯文本」输入", "Choose Email/Images or Plain Text input"))

            Text(inputDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(model.inputSource.editorTitle, systemImage: model.inputSource.editorSymbol)
                        .font(.headline)
                    Spacer()
                    Text(L10n.t("\(activeInputText.count) 字", "\(activeInputText.count) characters"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .textBackgroundColor))
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.secondary.opacity(0.22))
                    if activeInputText.isEmpty {
                        Text(model.inputSource.editorPlaceholder)
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: activeInputBinding)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        // Rebuild on source switch so the editor never keeps the
                        // other source's text or its undo stack.
                        .id(model.inputSource)
                        .onChange(of: activeInputText) { _, _ in
                            model.inputDidChange()
                        }
                }
                .frame(minHeight: 210, idealHeight: 280)
            }

            // Screenshots belong to the email/OCR pipeline only. Hiding them in
            // text mode is what makes "no OCR" visible to the user; buffered
            // images are kept so switching back does not lose them.
            if model.inputSource == .email {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("图片截图", systemImage: "photo.on.rectangle.angled")
                            .font(.headline)
                        Spacer()
                        if !model.images.isEmpty {
                            Button("清除全部", role: .destructive) {
                                model.clearImages()
                            }
                            .buttonStyle(.link)
                        }
                        Button {
                            model.pasteImageFromClipboard()
                        } label: {
                            Label("粘贴剪贴板图片", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    ImageDropArea(model: model)
                }

                if let imageMessage = model.imageMessage {
                    Label(L10n.dynamic(imageMessage), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 10) {
                if !model.apiKeyConfigured {
                    Label("未配置 DeepSeek API Key", systemImage: "key.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("设置") {
                        model.showAPIKeySheet = true
                    }
                    .buttonStyle(.link)
                } else {
                    Label(
                        L10n.t(model.apiKeyPresence == .inaccessible ? "Keychain Key 暂不可读" : "Keychain 中已有 API Key", model.apiKeyPresence == .inaccessible ? "Keychain key unreadable" : "API key found in Keychain"),
                        systemImage: model.apiKeyPresence == .inaccessible ? "lock.trianglebadge.exclamationmark" : "checkmark.seal"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isParsing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    model.parse()
                } label: {
                    Label("解析", systemImage: "sparkle.magnifyingglass")
                        .frame(minWidth: 78)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.hasInput || model.isParsing)
                .help("⌘↩ 解析")
            }
        }
        .padding(20)
    }

    // MARK: - Source-dependent strings and bindings

    private var activeInputText: String {
        model.inputSource == .email ? model.emailText : model.plainText
    }

    private var activeInputBinding: Binding<String> {
        model.inputSource == .email ? $model.emailText : $model.plainText
    }

    private var inputDescription: String {
        switch model.inputSource {
        case .email:
            return L10n.t(
                "粘贴 Outlook 邮件正文；截图可点图片区后按 ⌘V，或拖入 .png / .jpg。图片只在本机 OCR，只有文本会发给 DeepSeek。",
                "Paste an Outlook email body; for screenshots click the image area and press ⌘V, or drop a .png / .jpg. Images are OCR'd on-device; only text is sent to DeepSeek."
            )
        case .text:
            return L10n.t(
                "直接输入或粘贴任意文本。纯文本模式不做 OCR、不使用图片，文本会发给 DeepSeek。",
                "Type or paste any text. Plain Text mode does no OCR and uses no images; the text is sent to DeepSeek."
            )
        }
    }
}

private extension InputSource {
    var paneTitle: String {
        switch self {
        case .email: return L10n.t("邮件 / 截图", "Email / Images")
        case .text: return L10n.t("纯文本", "Plain Text")
        }
    }

    var editorTitle: String {
        switch self {
        case .email: return L10n.t("邮件正文", "Email body")
        case .text: return L10n.t("纯文本", "Plain text")
        }
    }

    var editorSymbol: String {
        switch self {
        case .email: return "envelope"
        case .text: return "text.alignleft"
        }
    }

    var editorPlaceholder: String {
        switch self {
        case .email:
            return L10n.t(
                "例如：\n报名截止 3月5日；活动 3月8日 14:00；地点 A101……",
                "e.g.\nDeadline March 5; event March 8 at 14:00; location A101…"
            )
        case .text:
            return L10n.t(
                "例如：\n3月5日前提交报名表；3月8日 14:00 说明会，地点 A101……",
                "e.g.\nSubmit the form by March 5; info session March 8 at 14:00 in A101…"
            )
        }
    }
}

private struct StatusPill: View {
    let status: WorkStatus

    private var color: Color {
        switch status {
        case .idle: return .secondary
        case .ocr, .deepSeek: return .accentColor
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if status == .idle {
                Circle().fill(color.opacity(0.7)).frame(width: 6, height: 6)
            } else {
                ProgressView().controlSize(.mini)
            }
            Text(status.text)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
    }
}

private struct ImageDropArea: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            if model.images.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(model.isDropTargeted ? Color.accentColor : Color.secondary)
                    Text("拖入图片，或点击此区域后按 ⌘V")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("截图仅在本机内存中处理，不落盘")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 108)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.images) { attachment in
                            ImageThumbnail(attachment: attachment) {
                                model.removeImage(id: attachment.id)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 116)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(model.isDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    model.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
        )
        .focusable()
        .focusEffectDisabled()
        .onPasteCommand(of: [.png, .tiff, .jpeg]) { providers in
            model.handlePasteProviders(providers)
        }
        .onDrop(
            of: [.fileURL, .image],
            isTargeted: $model.isDropTargeted
        ) { providers in
            model.handlePasteProviders(providers)
            return true
        }
        .help("点击后可 ⌘V 粘贴剪贴板截图；也可从 Finder 拖入图片")
    }
}

private struct ImageThumbnail: View {
    let attachment: ImageAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = attachment.nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                }
            }
            .frame(width: 120, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.2)))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.65))
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)

            VStack {
                Spacer()
                Text(attachment.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
            }
            .frame(width: 120, height: 88, alignment: .bottom)
        }
        .frame(width: 128, height: 96)
    }
}
