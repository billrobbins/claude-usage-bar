import Foundation

enum UsageWindow {
    static let session: TimeInterval = 5 * 60 * 60
    static let weekly: TimeInterval = 7 * 24 * 60 * 60
}

struct PaceInfo: Equatable {
    var elapsedPercent: Int   // 0–100, clamped
    var paceRatio: Double?    // utilization% ÷ elapsed%; nil near window start
}

/// `resetsAt − window` is the window start; ratio > 1 means usage is ahead of the clock.
func paceInfo(utilization: Int, resetsAt: Date?, window: TimeInterval, now: Date) -> PaceInfo? {
    guard let resetsAt = resetsAt, window > 0 else { return nil }
    let start = resetsAt.addingTimeInterval(-window)
    let fraction = min(1.0, max(0.0, now.timeIntervalSince(start) / window))
    let ratio: Double? = fraction < 0.01 ? nil : Double(utilization) / (fraction * 100)
    return PaceInfo(elapsedPercent: Int((fraction * 100).rounded()), paceRatio: ratio)
}

func paceSeverity(_ ratio: Double?) -> Severity? {
    guard let ratio = ratio else { return nil }
    if ratio >= 2.0 { return .red }
    if ratio >= 1.25 { return .amber }
    return nil
}

func formattedPace(_ ratio: Double) -> String {
    ratio >= 9.95 ? "9.9×+" : String(format: "%.1f×", ratio)
}
