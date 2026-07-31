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
    private let uaMajorKey = "claude_ua_major"

    /// Chrome major whose User-Agent last satisfied Cloudflare. Cached so the steady state
    /// costs a single request; re-derived by probing whenever a challenge comes back.
    private var uaMajor: Int?

    /// Set once a probe has tried every candidate without getting through, which means the
    /// clearance itself is dead rather than the User-Agent being wrong. Suppresses further
    /// probing so a stale cookie doesn't fire a burst of challenges every refresh tick.
    private var probeExhausted = false

    init() {
        loadCookie()
        lastNotifiedThreshold = UserDefaults.standard.integer(forKey: "last_notified_threshold")
        let stored = UserDefaults.standard.integer(forKey: uaMajorKey)
        uaMajor = stored > 0 ? stored : nil
    }

    var hasCookie: Bool { !cookie.isEmpty }

    func loadCookie() {
        cookie = UserDefaults.standard.string(forKey: "claude_session_cookie") ?? ""
    }

    func saveCookie(_ value: String) {
        cookie = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(cookie, forKey: "claude_session_cookie")
        // The clearance in a freshly pasted cookie was issued to whichever Chrome is installed
        // right now, so re-seed from that instead of trusting the previous cookie's major.
        rememberWorkingMajor(installedChromeMajor())
        probeExhausted = false
    }

    private func rememberWorkingMajor(_ major: Int?) {
        uaMajor = major
        if let major {
            UserDefaults.standard.set(major, forKey: uaMajorKey)
        } else {
            UserDefaults.standard.removeObject(forKey: uaMajorKey)
        }
    }

    func clearCookie() {
        cookie = ""
        UserDefaults.standard.removeObject(forKey: "claude_session_cookie")
        sessionUtil = 0; weeklyUtil = 0; sonnetUtil = 0
        hasSonnet = false; hasFetchedData = false; errorMessage = nil
        sessionResetsAt = nil; weeklyResetsAt = nil; sonnetResetsAt = nil
        lastNotifiedThreshold = 0
        UserDefaults.standard.set(0, forKey: "last_notified_threshold")
        rememberWorkingMajor(nil)
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
        fetch(url) { result in
            guard case .success(let data) = result,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = json["account"] as? [String: Any],
                  let orgId = account["lastActiveOrgId"] as? String else { completion(nil); return }
            completion(orgId)
        }
    }

    private func fetchUsage(orgId: String) {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else { return }
        fetch(url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                switch result {
                case .success(let data): self.apply(data)
                case .failure(let reason): self.errorMessage = reason.message
                }
            }
        }
    }

    // MARK: - Transport

    enum FetchFailure: Error {
        case network
        case challenge
        case unauthorized
        case http(Int)

        var message: String {
            switch self {
            case .network: return "Network error"
            case .challenge: return "Blocked by Cloudflare — re-copy your cookie from Chrome"
            case .unauthorized: return "Session expired — paste a fresh cookie"
            case .http(let code): return "HTTP \(code)"
            }
        }
    }

    private func makeRequest(_ url: URL, chromeMajor: Int) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        request.setValue(chromeUserAgent(major: chromeMajor), forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Issues the request under the most likely Chrome User-Agent, stepping through the
    /// remaining candidates only while Cloudflare answers with a challenge. Anything else —
    /// success, auth failure, transport error — settles immediately.
    private func fetch(_ url: URL, completion: @escaping (Result<Data, FetchFailure>) -> Void) {
        let all = userAgentCandidates(cachedMajor: uaMajor, installedMajor: installedChromeMajor())
        let candidates = probeExhausted ? Array(all.prefix(1)) : all
        attempt(url, candidates: candidates, index: 0) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure(.challenge) = result { self?.probeExhausted = true }
                else { self?.probeExhausted = false }
            }
            completion(result)
        }
    }

    private func attempt(_ url: URL,
                         candidates: [Int],
                         index: Int,
                         completion: @escaping (Result<Data, FetchFailure>) -> Void) {
        guard index < candidates.count else { completion(.failure(.challenge)); return }
        let major = candidates[index]
        let urlRequest = makeRequest(url, chromeMajor: major)
        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            if error != nil { completion(.failure(.network)); return }
            guard let http = response as? HTTPURLResponse else { completion(.failure(.network)); return }

            if isCloudflareChallenge(statusCode: http.statusCode,
                                     cfMitigated: http.value(forHTTPHeaderField: "cf-mitigated")) {
                self.attempt(url, candidates: candidates, index: index + 1, completion: completion)
                return
            }
            if http.statusCode == 200, let data = data {
                DispatchQueue.main.async { self.rememberWorkingMajor(major) }
                completion(.success(data))
                return
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                completion(.failure(.unauthorized)); return
            }
            completion(.failure(.http(http.statusCode)))
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
