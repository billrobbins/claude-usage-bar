import Foundation

/// Usage is refreshed every 5 minutes, so anything older than two missed ticks plus
/// slack means fetches are silently failing (typically a dead cookie / cf_clearance).
let usageStaleAfter: TimeInterval = 12 * 60

/// True when the displayed usage can't be trusted: the last fetch failed, or the last
/// successful one is older than `usageStaleAfter`.
func isUsageStale(lastUpdated: Date, hasError: Bool, now: Date) -> Bool {
    hasError || now.timeIntervalSince(lastUpdated) > usageStaleAfter
}

/// Compact age for the footer: "just now", "8m ago", "2h 5m ago".
func formattedAge(since date: Date, now: Date) -> String {
    let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
    if minutes < 1 { return "just now" }
    if minutes < 60 { return "\(minutes)m ago" }
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "\(h)h ago" : "\(h)h \(m)m ago"
}
