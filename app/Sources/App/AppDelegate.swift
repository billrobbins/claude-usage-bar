import AppKit
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, MenuBarIconUpdating {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private let settingsWindow = SettingsWindowController()

    let usageManager = UsageManager()
    let statusManager = StatusManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        usageManager.iconDelegate = self
        updateStatusIcon(sessionPercent: 0, stale: false)

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let hosting = NSHostingController(rootView: PopoverView(
            usage: usageManager,
            status: statusManager,
            onRefresh: { [weak self] in self?.refresh() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        ))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting

        usageManager.onUpdate = { [weak self] in self?.persistSnapshot() }
        statusManager.onUpdate = { [weak self] in self?.persistSnapshot() }

        NotificationService.requestAuthorization()
        refresh()

        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Timers don't fire during sleep, so without this the popover would show
        // pre-sleep numbers for up to five minutes after waking.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    // MARK: Actions

    private func refresh() {
        // Catches staleness by age alone (e.g. after sleep) before the fetch settles.
        if usageManager.isStale {
            updateStatusIcon(sessionPercent: usageManager.sessionUtil, stale: true)
        }
        usageManager.fetchUsage()
        statusManager.fetch()
    }

    func updateStatusIcon(sessionPercent: Int, stale: Bool) {
        guard let button = statusItem?.button else { return }
        if stale {
            button.image = staleStatusImage()
            button.attributedTitle = NSAttributedString(
                string: " \(sessionPercent)%",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                             .font: NSFont.menuBarFont(ofSize: 0)])
        } else {
            button.image = sparkStatusImage(forSeverity: Severity(utilization: sessionPercent))
            button.title = " \(sessionPercent)%"
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit Claude Usage", action: #selector(quit), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc private func refreshFromMenu() { refresh() }

    private func togglePopover() {
        if popover.isShown { closePopover() } else { openPopover() }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor); eventMonitor = nil }
    }

    @objc private func openSettings() {
        closePopover()
        settingsWindow.show(usage: usageManager, status: statusManager)
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    // MARK: Snapshot (widget seam)

    private func persistSnapshot() {
        let snapshot = UsageSnapshot(
            session: LimitSnapshot(utilization: usageManager.sessionUtil,
                                   resetsAt: usageManager.sessionResetsAt,
                                   hasData: usageManager.hasFetchedData),
            weekly: LimitSnapshot(utilization: usageManager.weeklyUtil,
                                  resetsAt: usageManager.weeklyResetsAt,
                                  hasData: usageManager.hasFetchedData),
            weeklySonnet: usageManager.hasSonnet
                ? LimitSnapshot(utilization: usageManager.sonnetUtil,
                                resetsAt: usageManager.sonnetResetsAt, hasData: true)
                : nil,
            statusIndicator: statusManager.effective,
            statusSummary: statusManager.effective == "none"
                ? "All Claude services operational" : statusManager.statusDescription,
            lastUpdated: usageManager.lastUpdated)
        _ = try? SnapshotStore.write(snapshot)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()   // no-op until a Phase-2 widget exists
        #endif
    }
}
