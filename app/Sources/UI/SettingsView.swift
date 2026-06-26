import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var usage: UsageManager
    @ObservedObject var status: StatusManager

    @State private var cookieInput = ""
    @State private var usageNotifications = UserDefaults.standard.object(forKey: "usage_notifications_enabled") as? Bool ?? true
    @State private var statusNotifications = UserDefaults.standard.bool(forKey: "status_notifications_enabled")
    @State private var openAtLogin = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                group("Session cookie") {
                    Text("Paste the full Cookie header from a claude.ai usage request.")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. claude.ai → Settings → Usage")
                        Text("2. Open DevTools (⌥⌘I) → Network tab")
                        Text("3. Refresh, click the 'usage' request")
                        Text("4. Copy the full 'Cookie' request header")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    PasteableTextField(text: $cookieInput, placeholder: "Paste cookie…")
                        .frame(height: 64)
                    HStack {
                        Button("Save & Fetch") {
                            guard !cookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            usage.saveCookie(cookieInput)
                            usage.fetchUsage()
                        }
                        .buttonStyle(.borderedProminent)
                        if usage.hasCookie {
                            Button("Clear") { cookieInput = ""; usage.clearCookie() }
                        }
                    }
                }

                Divider()

                group("Notifications") {
                    Toggle("Usage alerts at 25 / 50 / 75 / 90%", isOn: $usageNotifications)
                        .onChange(of: usageNotifications) { v in
                            UserDefaults.standard.set(v, forKey: "usage_notifications_enabled")
                        }
                    Toggle("Service status alerts", isOn: $statusNotifications)
                        .onChange(of: statusNotifications) { v in
                            UserDefaults.standard.set(v, forKey: "status_notifications_enabled")
                        }
                    Button("Test Notification") {
                        NotificationService.send(title: "Claude Usage Alert",
                                                 body: "Test — you've reached 75% of your session limit")
                    }
                    .controlSize(.small)
                }

                Divider()

                group("General") {
                    Toggle("Open at login", isOn: $openAtLogin)
                        .onChange(of: openAtLogin) { v in setOpenAtLogin(v) }
                }

                Divider()

                group("Status services to track") {
                    Text("Only tracked services trigger status alerts or show in the popover.")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(status.allComponents) { c in
                        Toggle(c.name, isOn: Binding(
                            get: { status.isTracked(c.id) },
                            set: { _ in status.toggleComponent(c.id) }
                        ))
                        .font(.caption)
                    }
                }

                Divider()

                group("About") {
                    Text("Personal build. Based on the MIT-licensed ClaudeUsageBar by Artzainnn.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Original project on GitHub →") {
                        if let url = URL(string: "https://github.com/Artzainnn/ClaudeUsageBar") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(20)
            .frame(width: 360, alignment: .leading)
        }
        .frame(width: 360, height: 560)
        .onAppear {
            openAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("open-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}
