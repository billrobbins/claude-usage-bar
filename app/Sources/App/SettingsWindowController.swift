import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func show(usage: UsageManager, status: StatusManager) {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(usage: usage, status: status))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Claude Usage Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
