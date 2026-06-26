import Foundation

func relativeTime(from date: Date, now: Date) -> String {
    let elapsed = Int(now.timeIntervalSince(date))
    if elapsed < 60 { return "just now" }
    if elapsed < 3600 {
        let m = elapsed / 60
        return "\(m) min\(m == 1 ? "" : "s") ago"
    }
    if elapsed < 86_400 {
        let h = elapsed / 3600
        return "\(h) hour\(h == 1 ? "" : "s") ago"
    }
    let d = elapsed / 86_400
    return "\(d) day\(d == 1 ? "" : "s") ago"
}

func shortName(_ raw: String) -> String {
    if let paren = raw.range(of: " (") {
        return String(raw[..<paren.lowerBound])
    }
    return raw
}

private func severityRank(forComponentStatus s: String) -> Int {
    switch s {
    case "operational":          return 0
    case "under_maintenance":    return 1
    case "degraded_performance": return 1
    case "partial_outage":       return 2
    case "major_outage":         return 3
    default:                     return 0
    }
}

func effectiveIndicator(components: [StatusComponent], tracked: Set<String>) -> String {
    let tracked = components.filter { tracked.contains($0.id) }
    let max = tracked.map { severityRank(forComponentStatus: $0.status) }.max() ?? 0
    switch max {
    case 0:  return "none"
    case 1:  return "minor"
    case 2:  return "major"
    default: return "critical"
    }
}

func statusContextLine(components: [StatusComponent],
                       affected: [AffectedComponent],
                       tracked: Set<String>,
                       lastChecked: Date?,
                       now: Date) -> String {
    let trackedComps = components.filter { tracked.contains($0.id) }
    let names = trackedComps.prefix(4).map { shortName($0.name) }.joined(separator: ", ")
    let extra = trackedComps.count > 4 ? " +\(trackedComps.count - 4)" : ""
    let summary = trackedComps.isEmpty ? "No services tracked" : "Tracks \(names)\(extra)"

    if effectiveIndicator(components: components, tracked: tracked) == "none" {
        if let last = lastChecked {
            return "\(summary) · checked \(relativeTime(from: last, now: now))"
        }
        return summary
    }

    let filteredAffected = affected.filter { tracked.contains($0.id) }
    if !filteredAffected.isEmpty {
        let a = filteredAffected.prefix(3).map { shortName($0.name) }.joined(separator: ", ")
        let more = filteredAffected.count > 3 ? " +\(filteredAffected.count - 3)" : ""
        return "Affects: \(a)\(more)"
    }
    if let last = lastChecked {
        return "Checked \(relativeTime(from: last, now: now))"
    }
    return ""
}
