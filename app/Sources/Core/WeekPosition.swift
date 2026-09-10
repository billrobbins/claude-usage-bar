import Foundation

/// Where in the window your usage "sits" if you'd spent it at a perfectly even rate:
/// windowStart + utilization% × window. For a Friday 6 PM weekly reset, 93% lands on
/// the following Friday around 6:14 AM — i.e. you've burned the week up to that clock time.
struct WindowPosition: Equatable {
    var usageDate: Date       // clock time the utilization corresponds to
    var leadSeconds: Double   // usageDate − now; positive means usage is ahead of the clock
}

func windowPosition(utilization: Int, resetsAt: Date?, window: TimeInterval, now: Date) -> WindowPosition? {
    guard let resetsAt = resetsAt, window > 0 else { return nil }
    let start = resetsAt.addingTimeInterval(-window)
    let fraction = min(1.0, max(0.0, Double(utilization) / 100.0))
    let usageDate = start.addingTimeInterval(fraction * window)
    return WindowPosition(usageDate: usageDate, leadSeconds: usageDate.timeIntervalSince(now))
}

func formattedWindowClock(_ date: Date,
                          locale: Locale = Locale(identifier: "en_US"),
                          timeZone: TimeZone = .current) -> String {
    let f = DateFormatter()
    f.locale = locale
    f.timeZone = timeZone
    f.dateFormat = "EEE h:mm a"
    return f.string(from: date)
}

/// "13h 42m ahead" / "2h behind" / "on pace".
func formattedLead(_ leadSeconds: Double) -> String {
    let magnitude = abs(leadSeconds)
    if magnitude < 5 * 60 { return "on pace" }
    let hours = Int(magnitude) / 3600
    let minutes = (Int(magnitude) % 3600) / 60
    let span = hours > 0 ? (minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h") : "\(minutes)m"
    return leadSeconds > 0 ? "\(span) ahead" : "\(span) behind"
}

/// Red when usage runs ahead of the clock, green when it lags behind, nil within 5 minutes.
func leadSeverity(_ leadSeconds: Double) -> Severity? {
    if abs(leadSeconds) < 5 * 60 { return nil }
    return leadSeconds > 0 ? .red : .green
}
