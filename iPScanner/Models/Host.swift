import Foundation

struct Host: Identifiable, Hashable {
    enum Status: Hashable {
        case scanning
        case alive
        case dead
    }

    let id: UUID
    var ip: String
    var hostname: String?
    var mac: String?
    var vendor: String?
    var rttMs: Double?
    var ttl: Int?
    var openPorts: [Int]
    var serviceTitle: String?
    var status: Status

    init(
        id: UUID = UUID(),
        ip: String,
        hostname: String? = nil,
        mac: String? = nil,
        vendor: String? = nil,
        rttMs: Double? = nil,
        ttl: Int? = nil,
        openPorts: [Int] = [],
        serviceTitle: String? = nil,
        status: Status = .scanning
    ) {
        self.id = id
        self.ip = ip
        self.hostname = hostname
        self.mac = mac
        self.vendor = vendor
        self.rttMs = rttMs
        self.ttl = ttl
        self.openPorts = openPorts
        self.serviceTitle = serviceTitle
        self.status = status
    }

    var ipNumeric: UInt32 { IPv4.uint32(from: ip) ?? 0 }
}
