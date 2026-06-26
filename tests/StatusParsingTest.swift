import Foundation

func testStatusParsing() {
    let json = """
    {
      "status": { "indicator": "minor", "description": "Partial Outage" },
      "components": [
        { "id": "c1", "name": "claude.ai", "status": "operational" },
        { "id": "c2", "name": "Claude Code", "status": "degraded_performance" }
      ],
      "incidents": [
        { "id": "i1", "name": "Elevated errors", "status": "investigating",
          "updated_at": "2026-06-26T12:00:00Z",
          "incident_updates": [ { "body": "We are looking into it.", "created_at": "2026-06-26T12:05:00Z" } ],
          "components": [ { "id": "c2" } ] },
        { "id": "i2", "name": "Old thing", "status": "resolved",
          "incident_updates": [] }
      ]
    }
    """.data(using: .utf8)!

    let s = try! parseStatusSummary(json)
    T.eq(s.indicator, "minor", "indicator")
    T.eq(s.description, "Partial Outage", "description")
    T.eq(s.components.count, 2, "two components")
    T.eq(s.affected.count, 1, "one affected (non-operational)")
    T.eq(s.affected.first?.id, "c2", "affected is c2")
    T.eq(s.incidents.count, 1, "resolved incident filtered out")
    T.eq(s.incidents.first?.latestUpdate, "We are looking into it.", "latest update body")
    T.eq(s.incidents.first?.componentIds, ["c2"], "incident component ids")
}
