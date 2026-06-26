import Foundation

struct StatusComponent: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String      // operational | degraded_performance | partial_outage | major_outage | under_maintenance
}

struct AffectedComponent: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String
}

struct StatusIncident: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String      // investigating | identified | monitoring | resolved | postmortem
    let latestUpdate: String
    let updatedAt: Date?
    let componentIds: [String]
}

struct ParsedStatus: Equatable {
    var indicator: String   // none | minor | major | critical
    var description: String
    var components: [StatusComponent]
    var affected: [AffectedComponent]
    var incidents: [StatusIncident]
}
