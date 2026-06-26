import Foundation

struct LimitSnapshot: Codable, Equatable {
    var utilization: Int
    var resetsAt: Date?
    var hasData: Bool
}

struct UsageSnapshot: Codable, Equatable {
    var schemaVersion: Int = 1
    var session: LimitSnapshot
    var weekly: LimitSnapshot
    var weeklySonnet: LimitSnapshot?
    var statusIndicator: String
    var statusSummary: String
    var lastUpdated: Date
}

enum SnapshotStore {
    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("ClaudeUsageBar", isDirectory: true)
    }
    static var fileURL: URL { directoryURL.appendingPathComponent("usage-snapshot.json") }

    static func encode(_ snapshot: UsageSnapshot) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> UsageSnapshot {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(UsageSnapshot.self, from: data)
    }

    @discardableResult
    static func write(_ snapshot: UsageSnapshot) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL,
                                                withIntermediateDirectories: true)
        try encode(snapshot).write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func read() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decode(data)
    }
}
