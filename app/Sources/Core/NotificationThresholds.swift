import Foundation

func thresholdUpdate(percentage: Int,
                     lastNotified: Int,
                     thresholds: [Int] = [25, 50, 75, 90]) -> (toFire: [Int], newLastNotified: Int) {
    var toFire: [Int] = []
    var last = lastNotified
    for t in thresholds where percentage >= t && last < t {
        toFire.append(t)
        last = t
    }
    if percentage < last {
        last = thresholds.filter { $0 <= percentage }.last ?? 0
    }
    return (toFire, last)
}
