import Foundation

enum Severity: Equatable {
    case green, amber, red

    init(utilization: Int) {
        switch utilization {
        case ..<70:   self = .green
        case 70..<90: self = .amber
        default:      self = .red
        }
    }
}
