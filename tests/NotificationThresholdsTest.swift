import Foundation

func testNotificationThresholds() {
    let a = thresholdUpdate(percentage: 80, lastNotified: 0)
    T.eq(a.toFire, [25, 50, 75], "80% from 0 fires 25/50/75")
    T.eq(a.newLastNotified, 75, "new last = 75")

    let b = thresholdUpdate(percentage: 95, lastNotified: 0)
    T.eq(b.toFire, [25, 50, 75, 90], "95% fires all")
    T.eq(b.newLastNotified, 90, "new last = 90")

    let c = thresholdUpdate(percentage: 80, lastNotified: 75)
    T.eq(c.toFire, [], "no re-fire when already at 75")
    T.eq(c.newLastNotified, 75, "stays 75")

    let d = thresholdUpdate(percentage: 30, lastNotified: 75)
    T.eq(d.toFire, [], "drop to 30 fires nothing")
    T.eq(d.newLastNotified, 25, "re-arms down to 25")

    let e = thresholdUpdate(percentage: 10, lastNotified: 0)
    T.eq(e.toFire, [], "10% fires nothing")
    T.eq(e.newLastNotified, 0, "stays 0")
}
