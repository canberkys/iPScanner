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
        let vendorStatus: VendorStatus?
        let vendor: String?
        let rttMs: Double?
        let ttl: Int?
        let netbiosName: String?
        let workgroup: String?
        let openPorts: [Int]
        let serviceTitle: String?
        let status: Host.Status

        init(ip: String, hostname: String?, mac: String?, vendor: String?, vendorStatus: VendorStatus? = nil,
             rttMs: Double?, ttl: Int?, netbiosName: String? = nil,
             workgroup: String? = nil, openPorts: [Int], serviceTitle: String?,
             status: Host.Status = .alive) {
            self.ip = ip
            self.hostname = hostname
            self.mac = mac
            self.vendor = vendor
            self.vendorStatus = vendorStatus
            self.rttMs = rttMs
            self.ttl = ttl
            self.netbiosName = netbiosName
            self.workgroup = workgroup
            self.openPorts = openPorts
            self.serviceTitle = serviceTitle
            self.status = status
        }

        // Custom decoder lets older `.ipscan.json` files (no `ttl` / `netbiosName`
        // / `workgroup`) still load.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let ip = try c.decode(String.self, forKey: .ip)
            // Snapshot files can be hand-edited or come from an untrusted source.
            // The `ip` field ends up embedded in shell scripts (HostActions), so a
            // non-IPv4 value here must be rejected at decode time, not sanitized later.
            guard IPv4.uint32(from: ip) != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .ip, in: c, debugDescription: "\"\(ip)\" is not a valid IPv4 address"
                )
            }
            self.ip = ip
            self.hostname = try c.decodeIfPresent(String.self, forKey: .hostname)
            self.mac = try c.decodeIfPresent(String.self, forKey: .mac)
            self.vendor = try c.decodeIfPresent(String.self, forKey: .vendor)
            self.vendorStatus = try c.decodeIfPresent(VendorStatus.self, forKey: .vendorStatus)
            self.rttMs = try c.decodeIfPresent(Double.self, forKey: .rttMs)
            self.ttl = try c.decodeIfPresent(Int.self, forKey: .ttl)
            self.netbiosName = try c.decodeIfPresent(String.self, forKey: .netbiosName)
            self.workgroup = try c.decodeIfPresent(String.self, forKey: .workgroup)
            self.openPorts = try c.decodeIfPresent([Int].self, forKey: .openPorts) ?? []
            self.serviceTitle = try c.decodeIfPresent(String.self, forKey: .serviceTitle)
            // Older `.ipscan.json` files predate this field; they only ever recorded
            // alive hosts, so `.alive` is the correct default for them.
            self.status = try c.decodeIfPresent(Host.Status.self, forKey: .status) ?? .alive
        }
    }
}

enum SnapshotIO {
    static func encode(_ snapshot: ScanSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    enum SnapshotError: LocalizedError, Equatable {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "This scan file uses format \(version), which is newer than this version of iPScanner supports (\(ScanSnapshot.currentVersion)). Update iPScanner and try again."
            }
        }
    }

    private struct VersionProbe: Decodable { let version: Int }

    static func decode(_ data: Data) throws -> ScanSnapshot {
        // Check the format first so a newer file gets a clear message instead of a
        // generic decoding error or a partially understood load.
        if let probe = try? JSONDecoder().decode(VersionProbe.self, from: data),
           probe.version > ScanSnapshot.currentVersion {
            throw SnapshotError.unsupportedVersion(probe.version)
        }
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
