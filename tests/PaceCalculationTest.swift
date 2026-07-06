import Foundation

func testPaceCalculation() {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    // No reset date → no pace info at all
    T.ok(paceInfo(utilization: 35, resetsAt: nil, window: UsageWindow.weekly, now: now) == nil,
         "nil resetsAt → nil")

    // Mid-window: reset is 74% of a week away → 26% elapsed
    let midResets = now.addingTimeInterval(UsageWindow.weekly * 0.74)
    let mid = paceInfo(utilization: 35, resetsAt: midResets, window: UsageWindow.weekly, now: now)
    T.eq(mid?.elapsedPercent, 26, "mid-window elapsed percent")
    T.ok(abs((mid?.paceRatio ?? 0) - 35.0 / 26.0) < 0.001, "mid-window ratio ≈ 1.35")

    // Stale reset date in the past → clamps to 100% elapsed, ratio = util/100
    let stale = paceInfo(utilization: 35, resetsAt: now.addingTimeInterval(-60),
                         window: UsageWindow.weekly, now: now)
    T.eq(stale?.elapsedPercent, 100, "past reset clamps to 100")
    T.ok(abs((stale?.paceRatio ?? 0) - 0.35) < 0.001, "past reset ratio 0.35")

    // Window barely started (0.4% elapsed) → percent 0, ratio suppressed
    let fresh = paceInfo(utilization: 3, resetsAt: now.addingTimeInterval(UsageWindow.weekly * 0.996),
                         window: UsageWindow.weekly, now: now)
    T.eq(fresh?.elapsedPercent, 0, "fresh window elapsed 0")
    T.ok(fresh?.paceRatio == nil, "fresh window ratio suppressed")

    // Session window: 2.5h into 5h at 40% used → 50% elapsed, 0.8× pace
    let sess = paceInfo(utilization: 40, resetsAt: now.addingTimeInterval(UsageWindow.session / 2),
                        window: UsageWindow.session, now: now)
    T.eq(sess?.elapsedPercent, 50, "session half elapsed")
    T.ok(abs((sess?.paceRatio ?? 0) - 0.8) < 0.001, "session ratio 0.8")

    // Severity thresholds
    T.ok(paceSeverity(nil) == nil, "nil ratio → no severity")
    T.ok(paceSeverity(1.24) == nil, "1.24 → neutral")
    T.eq(paceSeverity(1.25), .amber, "1.25 → amber")
    T.eq(paceSeverity(1.99), .amber, "1.99 → amber")
    T.eq(paceSeverity(2.0), .red, "2.0 → red")

    // Display formatting
    T.eq(formattedPace(35.0 / 26.0), "1.3×", "one decimal")
    T.eq(formattedPace(0.8), "0.8×", "under pace format")
    T.eq(formattedPace(9.94), "9.9×", "just under cap")
    T.eq(formattedPace(9.95), "9.9×+", "cap boundary")
    T.eq(formattedPace(47.0), "9.9×+", "way over cap")
}
