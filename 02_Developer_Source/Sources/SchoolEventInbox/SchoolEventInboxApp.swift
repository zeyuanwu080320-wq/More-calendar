import SwiftUI

@main
struct SchoolEventInboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @StateObject private var language = LanguageManager.shared

    var body: some Scene {
        WindowGroup("More calendar") {
            ContentView(model: model)
                .environmentObject(language)
                .environment(\.locale, language.language.locale)
                .id(language.language.rawValue)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .defaultSize(width: 1220, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L10n.t("学校事件", "School Event")) {
                Button(L10n.t("解析", "Parse")) {
                    model.parse()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.hasInput || model.isParsing)

                Divider()

                Button(model.writeActionTitle) {
                    model.writeToCalendar()
                }
                .disabled(!model.canTapWrite)

                Button(L10n.t("导出最近 30 条日志", "Export last 30 logs")) {
                    model.exportLogs()
                }

                Divider()

                Button(L10n.t("管理事件", "Managed Events")) {
                    model.showManagedEvents = true
                }
                .disabled(model.managedEventProvider == nil)
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}
