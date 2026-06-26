import Foundation
import Combine

protocol MenuBarIconUpdating: AnyObject {
    func updateStatusIcon(sessionPercent: Int)
}

final class UsageManager: ObservableObject {
    @Published var sessionUtil = 0
    @Published var weeklyUtil = 0
    @Published var sonnetUtil = 0
    @Published var hasSonnet = false
    @Published var sessionResetsAt: Date?
    @Published var weeklyResetsAt: Date?
    @Published var sonnetResetsAt: Date?
    @Published var hasFetchedData = false
    @Published var lastUpdated = Date()
    @Published var errorMessage: String?
    @Published var isLoading = false

    weak var iconDelegate: MenuBarIconUpdating?
    var onUpdate: (() -> Void)?

    private var cookie = ""
    private var lastNotifiedThreshold = 0
    private let usageNotificationsKey = "usage_notifications_enabled"

    init() { loadCookie(); lastNotifiedThreshold = UserDefaults.standard.integer(forKey: "last_notified_threshold") }

    var hasCookie: Bool { !cookie.isEmpty }

    func loadCookie() {
        cookie = UserDefaults.standard.string(forKey: "claude_session_cookie") ?? ""
    }

    func saveCookie(_ value: String) {
        cookie = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(cookie, forKey: "claude_session_cookie")
    }

    func clearCookie() {
        cookie = ""
        UserDefaults.standard.removeObject(forKey: "claude_session_cookie")
        sessionUtil = 0; weeklyUtil = 0; sonnetUtil = 0
        hasSonnet = false; hasFetchedData = false; errorMessage = nil
        sessionResetsAt = nil; weeklyResetsAt = nil; sonnetResetsAt = nil
        lastNotifiedThreshold = 0
        UserDefaults.standard.set(0, forKey: "last_notified_threshold")
        iconDelegate?.updateStatusIcon(sessionPercent: 0)
        onUpdate?()
    }

    // MARK: - Fetch

    func fetchUsage() {
        guard !cookie.isEmpty else {
            DispatchQueue.main.async { self.errorMessage = "Session cookie not set" }
            return
        }
        isLoading = true
        errorMessage = nil
        resolveOrgId { [weak self] orgId in
            guard let self = self, let orgId = orgId else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.errorMessage = "Could not get org id from cookie"
                }
                return
            }
            self.fetchUsage(orgId: orgId)
        }
    }

    private func resolveOrgId(_ completion: @escaping (String?) -> Void) {
        for part in cookie.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("lastActiveOrg=") {
                completion(String(trimmed.dropFirst("lastActiveOrg=".count)))
                return
            }
        }
        guard let url = URL(string: "https://claude.ai/api/bootstrap") else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(cookie)", forHTTPHeaderField: "Cookie")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = json["account"] as? [String: Any],
                  let orgId = account["lastActiveOrgId"] as? String else { completion(nil); return }
            completion(orgId)
        }.resume()
    }

    private func fetchUsage(orgId: String) {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else { return }
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                         forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if error != nil { self.errorMessage = "Network error"; return }
                guard let http = response as? HTTPURLResponse else { self.errorMessage = "Invalid response"; return }
                guard http.statusCode == 200, let data = data else {
                    self.errorMessage = "HTTP \(http.statusCode)"; return
                }
                self.apply(data)
            }
        }.resume()
    }

    private func apply(_ data: Data) {
        guard let parsed = try? parseUsage(data) else { errorMessage = "Parse error"; return }
        if let s = parsed.session { sessionUtil = s.utilization; sessionResetsAt = s.resetsAt }
        if let w = parsed.weekly { weeklyUtil = w.utilization; weeklyResetsAt = w.resetsAt }
        if let so = parsed.sonnet { hasSonnet = true; sonnetUtil = so.utilization; sonnetResetsAt = so.resetsAt }
        else { hasSonnet = false }
        lastUpdated = Date()
        hasFetchedData = true
        errorMessage = nil
        iconDelegate?.updateStatusIcon(sessionPercent: sessionUtil)
        fireThresholdNotifications()
        onUpdate?()
    }

    private func fireThresholdNotifications() {
        guard UserDefaults.standard.object(forKey: usageNotificationsKey) == nil
                || UserDefaults.standard.bool(forKey: usageNotificationsKey) else { return }
        let result = thresholdUpdate(percentage: sessionUtil, lastNotified: lastNotifiedThreshold)
        for t in result.toFire {
            NotificationService.send(title: "Claude Usage Alert",
                                     body: "You've reached \(sessionUtil)% of your 5-hour session limit")
            _ = t
        }
        lastNotifiedThreshold = result.newLastNotified
        UserDefaults.standard.set(lastNotifiedThreshold, forKey: "last_notified_threshold")
    }
}
