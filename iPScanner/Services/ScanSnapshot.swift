import Foundation

struct ScanSnapshot: Codable {
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    let rangeInput: String
    let hosts: [HostRecord]
    let labels: [String: String]

    struct HostRecord: Codable, Equatable, Hashable, Sendable {
        let ip: String
        let hostname: String?
        let mac: String?
        let vendor: String?
        let rttMs: Double?
        let openPorts: [Int]
        let serviceTitle: String?
    }
}

enum SnapshotIO {
    static func encode(_ snapshot: ScanSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> ScanSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScanSnapshot.self, from: data)
    }

    static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "iPScanner-\(formatter.string(from: Date())).ipscan.json"
    }
}
