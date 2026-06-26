import Foundation

enum StatusParseError: Error { case invalidJSON }

func parseStatusSummary(_ data: Data) throws -> ParsedStatus {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let status = json["status"] as? [String: Any],
          let indicator = status["indicator"] as? String,
          let desc = status["description"] as? String else {
        throw StatusParseError.invalidJSON
    }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoNoFrac = ISO8601DateFormatter()
    isoNoFrac.formatOptions = [.withInternetDateTime]

    var incidents: [StatusIncident] = []
    if let raw = json["incidents"] as? [[String: Any]] {
        for inc in raw {
            guard let id = inc["id"] as? String,
                  let name = inc["name"] as? String,
                  let st = inc["status"] as? String else { continue }
            if st == "resolved" || st == "postmortem" { continue }
            let updates = inc["incident_updates"] as? [[String: Any]] ?? []
            let latest = (updates.first?["body"] as? String) ?? ""
            let dateStr = (updates.first?["created_at"] as? String) ?? (inc["updated_at"] as? String)
            let updatedAt = dateStr.flatMap { iso.date(from: $0) ?? isoNoFrac.date(from: $0) }
            let compIds = (inc["components"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            incidents.append(StatusIncident(id: id, name: name, status: st,
                                            latestUpdate: latest, updatedAt: updatedAt,
                                            componentIds: compIds))
        }
    }

    var components: [StatusComponent] = []
    var affected: [AffectedComponent] = []
    if let raw = json["components"] as? [[String: Any]] {
        for c in raw {
            guard let id = c["id"] as? String,
                  let name = c["name"] as? String,
                  let st = c["status"] as? String else { continue }
            components.append(StatusComponent(id: id, name: name, status: st))
            if st != "operational" {
                affected.append(AffectedComponent(id: id, name: name, status: st))
            }
        }
    }

    return ParsedStatus(indicator: indicator, description: desc,
                        components: components, affected: affected, incidents: incidents)
}
