import Foundation

func testStatusContext() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    T.eq(relativeTime(from: now.addingTimeInterval(-30), now: now), "just now", "30s -> just now")
    T.eq(relativeTime(from: now.addingTimeInterval(-180), now: now), "3 mins ago", "3m")
    T.eq(relativeTime(from: now.addingTimeInterval(-60), now: now), "1 min ago", "1m singular")
    T.eq(relativeTime(from: now.addingTimeInterval(-7200), now: now), "2 hours ago", "2h")

    T.eq(shortName("Claude API (api.anthropic.com)"), "Claude API", "strips parens")

    let comps = [
        StatusComponent(id: "a", name: "claude.ai", status: "operational"),
        StatusComponent(id: "b", name: "Claude Code", status: "degraded_performance"),
    ]
    T.eq(effectiveIndicator(components: comps, tracked: ["a"]), "none", "tracking only healthy -> none")
    T.eq(effectiveIndicator(components: comps, tracked: ["a", "b"]), "minor", "tracking degraded -> minor")

    let line = statusContextLine(components: comps, affected: [], tracked: ["a"],
                                 lastChecked: now.addingTimeInterval(-180), now: now)
    T.eq(line, "Tracks claude.ai · checked 3 mins ago", "operational context line")
}
