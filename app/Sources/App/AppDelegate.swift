import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    let usageManager = UsageManager()
    let statusManager = StatusManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Claude Usage")
            button.title = " —%"
            button.target = self
            button.action = #selector(quit)
        }
        NotificationService.requestAuthorization()
        usageManager.fetchUsage()
        statusManager.fetch()
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
