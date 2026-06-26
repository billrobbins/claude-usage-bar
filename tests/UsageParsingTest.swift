import Foundation

func testUsageParsing() {
    let json = """
    {
      "five_hour":  { "utilization": 15.0, "resets_at": "2026-06-26T18:10:00.000000Z" },
      "seven_day":  { "utilization": 65,   "resets_at": "2026-06-26T22:00:00Z" },
      "seven_day_sonnet": { "utilization": 12.0, "resets_at": "2026-06-26T22:00:00Z" }
    }
    """.data(using: .utf8)!

    let u = try! parseUsage(json)
    T.eq(u.session?.utilization, 15, "session util")
    T.eq(u.weekly?.utilization, 65, "weekly util (int form)")
    T.eq(u.sonnet?.utilization, 12, "sonnet util")
    T.ok(u.session?.resetsAt != nil, "session reset parsed (fractional seconds)")
    T.ok(u.weekly?.resetsAt != nil, "weekly reset parsed (no fractional seconds)")

    let noSonnet = """
    { "five_hour": { "utilization": 5, "resets_at": "2026-06-26T18:10:00Z" },
      "seven_day": { "utilization": 5, "resets_at": "2026-06-26T22:00:00Z" } }
    """.data(using: .utf8)!
    let u2 = try! parseUsage(noSonnet)
    T.ok(u2.sonnet == nil, "no sonnet key -> nil")
}
