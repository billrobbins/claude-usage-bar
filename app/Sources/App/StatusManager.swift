import Foundation
import Combine

private let defaultTrackedComponents: [StatusComponent] = [
    StatusComponent(id: "c-claude-ai",      name: "claude.ai",                            status: "operational"),
    StatusComponent(id: "c-claude-console", name: "Claude Console (platform.claude.com)", status: "operational"),
    StatusComponent(id: "c-claude-api",     name: "Claude API (api.anthropic.com)",       status: "operational"),
    StatusComponent(id: "c-claude-code",    name: "Claude Code",                          status: "operational"),
    StatusComponent(id: "c-claude-cowork",  name: "Claude Cowork",                        status: "operational"),
    StatusComponent(id: "c-claude-gov",     name: "Claude for Government",                status: "operational"),
]

final class StatusManager: ObservableObject {
    @Published var indicator = "none"
    @Published var statusDescription = "All systems operational"
    @Published var incidents: [StatusIncident] = []
    @Published var affected: [AffectedComponent] = []
    @Published var allComponents: [StatusComponent] = defaultTrackedComponents
    @Published var selectedComponentIds: Set<String> =
        Set(defaultTrackedComponents.map { $0.id }.filter { $0 != "c-claude-gov" })
    @Published var lastUpdated: Date?
    @Published var hasFetched = false

    var onUpdate: (() -> Void)?
    private let endpoint = URL(string: "https://status.claude.com/api/v2/summary.json")!

    init() {
        if let saved = UserDefaults.standard.array(forKey: "tracked_component_ids") as? [String] {
            selectedComponentIds = Set(saved)
        }
    }

    var effective: String { effectiveIndicator(components: allComponents, tracked: selectedComponentIds) }

    func contextLine(now: Date) -> String {
        statusContextLine(components: allComponents, affected: affected,
                          tracked: selectedComponentIds, lastChecked: lastUpdated, now: now)
    }

    func isTracked(_ id: String) -> Bool { selectedComponentIds.contains(id) }

    func toggleComponent(_ id: String) {
        if selectedComponentIds.contains(id) { selectedComponentIds.remove(id) }
        else { selectedComponentIds.insert(id) }
        UserDefaults.standard.set(Array(selectedComponentIds), forKey: "tracked_component_ids")
    }

    func fetch() {
        let request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data, let parsed = try? parseStatusSummary(data) else { return }
            DispatchQueue.main.async { self.apply(parsed) }
        }.resume()
    }

    private func apply(_ parsed: ParsedStatus) {
        let wasFirst = !hasFetched
        let previousEffective = UserDefaults.standard.string(forKey: "last_effective_indicator")

        indicator = parsed.indicator
        statusDescription = parsed.description
        incidents = parsed.incidents
        affected = parsed.affected
        if !parsed.components.isEmpty {
            allComponents = parsed.components
            let realIds = Set(parsed.components.map { $0.id })
            let neverConfigured = UserDefaults.standard.array(forKey: "tracked_component_ids") == nil
            // If a previously-saved selection is non-empty but shares no IDs with the
            // real components (e.g. placeholder IDs persisted before the first fetch,
            // or status.com changed its IDs), re-seed defaults. An empty selection is
            // a deliberate "track nothing" choice and is left alone.
            let savedIsStale = !selectedComponentIds.isEmpty && selectedComponentIds.isDisjoint(with: realIds)
            if neverConfigured || savedIsStale {
                let defaults = parsed.components
                    .filter { !$0.name.localizedCaseInsensitiveContains("Government") }
                    .map { $0.id }
                selectedComponentIds = Set(defaults)
                UserDefaults.standard.set(Array(selectedComponentIds), forKey: "tracked_component_ids")
            }
        }
        lastUpdated = Date()
        hasFetched = true

        let eff = effective
        if !wasFirst, let prev = previousEffective, prev != eff,
           UserDefaults.standard.bool(forKey: "status_notifications_enabled") {
            if eff == "none" {
                NotificationService.send(title: "Claude is back online", body: "All systems operational")
            } else {
                NotificationService.send(title: "Claude status: \(parsed.description)",
                                         body: "Visit status.claude.com for details")
            }
        }
        UserDefaults.standard.set(eff, forKey: "last_effective_indicator")
        onUpdate?()
    }
}
