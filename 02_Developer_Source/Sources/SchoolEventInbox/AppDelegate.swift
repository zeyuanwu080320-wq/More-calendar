import AppKit
import SwiftUI

/// Fallback for the rare case where SwiftUI restores a closed WindowGroup and
/// leaves the app running with no visible main window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fallbackWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            self.ensureMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ensureMainWindow()
        return true
    }

    func applicationShouldSaveApplicationState(_ sender: NSApplication) -> Bool { false }
    func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool { false }

    @MainActor
    private func ensureMainWindow() {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let fallbackWindow {
            fallbackWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = ContentView(model: AppModel.shared)
            .environmentObject(LanguageManager.shared)
            .environment(\.locale, LanguageManager.shared.language.locale)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "More calendar"
        window.contentViewController = controller
        window.minSize = NSSize(width: 1080, height: 700)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        fallbackWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
