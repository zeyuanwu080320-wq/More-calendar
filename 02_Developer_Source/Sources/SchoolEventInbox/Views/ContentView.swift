import AppKit
import SchoolEventInboxCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                InputPane(model: model)
                    .frame(minWidth: 430, idealWidth: 450, maxWidth: 520)
                Divider()
                EventListPane(model: model)
                    .frame(minWidth: 580, maxWidth: .infinity)
            }
            Divider()
            FooterBar(model: model)
        }
        .frame(minWidth: 1080, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            centerWindowIfNeeded()
            #if DEBUG
            model.loadDemoIfRequested()
            #endif
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.showAPIKeySheet = true
                    model.apiKeyMessage = nil
                    model.apiKeyDraft = ""
                } label: {
                    Label(
                        L10n.t(model.apiKeyConfigured ? "API Key 已配置" : "设置 API Key", model.apiKeyConfigured ? "API key configured" : "Set API Key"),
                        systemImage: model.apiKeyConfigured ? "key.fill" : "key"
                    )
                }
                .help(L10n.t("DeepSeek API Key 保存在 macOS Keychain", "The DeepSeek API key is stored in the macOS Keychain"))

                Button {
                    model.refreshCalendarStatus()
                } label: {
                    Label(L10n.t("刷新日历权限", "Refresh Calendar Access"), systemImage: "calendar.badge.clock")
                }
                .help(L10n.t("重新读取 Apple 日历授权状态", "Re-read the Apple Calendar authorization state"))

                Button {
                    model.showManagedEvents = true
                } label: {
                    // Was deliberately `Text(verbatim:)` while the entry point
                    // was still being settled; it now follows the UI language
                    // like the menu item and the sheet header.
                    Text(L10n.t("管理事件", "Managed Events"))
                }
                // Reminders have no time slot to browse, delete or shift, so
                // this entry is unavailable while that target is selected.
                .disabled(model.managedEventProvider == nil)
                .help(L10n.t("管理本工具创建的事件", "Manage events created by this app"))

                Button {
                    language.toggle()
                    // Rename the per-type Apple calendars to the new language so
                    // the Calendar sidebar matches the app. No-ops silently when
                    // full calendar access is missing.
                    Task { await model.syncCalendarLanguage() }
                } label: {
                    Text(language.language.shortLabel)
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: 20)
                }
                .help(L10n.t("切换界面语言", "Switch UI language"))
            }
        }
        .sheet(isPresented: $model.showAPIKeySheet) {
            APIKeySheet(model: model)
        }
        .sheet(isPresented: $model.showManagedEvents) {
            // Apple Calendar always supports management, so this branch always
            // renders — the panel looks and behaves exactly as in V1.0.
            if let provider = model.managedEventProvider {
                ManagedEventsView(provider: provider)
            }
        }
        .alert("清空本地日志？", isPresented: $model.showClearLogConfirmation) {
            Button("清空", role: .destructive) {
                model.clearLogs()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除本地 log.jsonl，不会删除 App、源码或其他文件。清空后无法恢复。")
        }
    }

    /// WindowGroup may restore a frame that is mostly off-screen after display
    /// or resolution changes. Keep the one tool window usable.
    private func centerWindowIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let window = NSApp.windows.first(where: { $0.title == "More calendar" }),
                  let screen = window.screen ?? NSScreen.main else {
                return
            }
            let visible = screen.visibleFrame.insetBy(dx: -1, dy: -1)
            if !visible.contains(window.frame) {
                window.center()
            }
        }
    }
}
