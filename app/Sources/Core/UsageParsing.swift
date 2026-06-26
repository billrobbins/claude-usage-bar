import Foundation

struct ParsedLimit: Equatable {
    var utilization: Int
    var resetsAt: Date?
}

struct ParsedUsage: Equatable {
    var session: ParsedLimit?
    var weekly: ParsedLimit?
    var sonnet: ParsedLimit?
}

enum UsageParseError: Error { case invalidJSON }

func parseUsage(_ data: Data) throws -> ParsedUsage {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UsageParseError.invalidJSON
    }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoNoFrac = ISO8601DateFormatter()
    isoNoFrac.formatOptions = [.withInternetDateTime]

    func limit(_ key: String) -> ParsedLimit? {
        guard let obj = json[key] as? [String: Any] else { return nil }
        let util: Int
        if let d = obj["utilization"] as? Double { util = Int(d) }
        else if let i = obj["utilization"] as? Int { util = i }
        else { util = 0 }
        let resets = (obj["resets_at"] as? String)
            .flatMap { iso.date(from: $0) ?? isoNoFrac.date(from: $0) }
        return ParsedLimit(utilization: util, resetsAt: resets)
    }

    return ParsedUsage(session: limit("five_hour"),
                       weekly: limit("seven_day"),
                       sonnet: limit("seven_day_sonnet"))
}
