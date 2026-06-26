import Foundation

func testSnapshotRoundTrip() {
    // whole-second dates so .iso8601 round-trips exactly
    let reset = Date(timeIntervalSince1970: 1_790_000_000)
    let updated = Date(timeIntervalSince1970: 1_789_990_000)
    let snap = UsageSnapshot(
        schemaVersion: 1,
        session: LimitSnapshot(utilization: 15, resetsAt: reset, hasData: true),
        weekly: LimitSnapshot(utilization: 65, resetsAt: reset, hasData: true),
        weeklySonnet: LimitSnapshot(utilization: 12, resetsAt: reset, hasData: true),
        statusIndicator: "none",
        statusSummary: "All Claude services operational",
        lastUpdated: updated)

    let data = try! SnapshotStore.encode(snap)
    let back = try! SnapshotStore.decode(data)
    T.eq(back, snap, "snapshot encode/decode round-trips")

    let s = String(data: data, encoding: .utf8)!
    T.ok(s.contains("\"schemaVersion\""), "json has schemaVersion")
    T.ok(SnapshotStore.fileURL.path.hasSuffix("ClaudeUsageBar/usage-snapshot.json"),
         "file path is correct")
}
