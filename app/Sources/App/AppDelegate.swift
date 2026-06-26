import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, MenuBarIconUpdating {
    private var statusItem: NSStatusItem!
    let usageManager = UsageManager()
    let statusManager = StatusManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(quit)
        }
        usageManager.iconDelegate = self
        updateStatusIcon(sessionPercent: 0)
        NotificationService.requestAuthorization()
        usageManager.fetchUsage()
        statusManager.fetch()
    }

    func updateStatusIcon(sessionPercent: Int) {
        guard let button = statusItem?.button else { return }
        button.image = sparkStatusImage(forSeverity: Severity(utilization: sessionPercent))
        button.title = " \(sessionPercent)%"
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
