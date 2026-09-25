import Foundation

func testUsageFreshness() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    T.eq(isUsageStale(lastUpdated: now.addingTimeInterval(-60), hasError: false, now: now), false,
         "fresh fetch is not stale")
    T.eq(isUsageStale(lastUpdated: now.addingTimeInterval(-60), hasError: true, now: now), true,
         "any fetch error marks usage stale")
    T.eq(isUsageStale(lastUpdated: now.addingTimeInterval(-11 * 60), hasError: false, now: now), false,
         "11 minutes old is still fresh")
    T.eq(isUsageStale(lastUpdated: now.addingTimeInterval(-53 * 60), hasError: false, now: now), true,
         "53 minutes old is stale")

    T.eq(formattedAge(since: now.addingTimeInterval(-20), now: now), "just now", "age under a minute")
    T.eq(formattedAge(since: now.addingTimeInterval(-53 * 60), now: now), "53m ago", "age in minutes")
    T.eq(formattedAge(since: now.addingTimeInterval(-120 * 60), now: now), "2h ago", "whole hours")
    T.eq(formattedAge(since: now.addingTimeInterval(-125 * 60), now: now), "2h 5m ago", "hours and minutes")
}
