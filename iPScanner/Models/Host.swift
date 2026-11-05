import Foundation

struct Host: Identifiable, Hashable {
    enum Status: Hashable, Codable {
        case scanning
        case alive
        case dead
    }

    let id: UUID
    var ip: String
    var hostname: String?
    var mac: String?
    var vendorStatus: VendorStatus?
    var vendor: String?
    var rttMs: Double?
    var ttl: Int?
    var netbiosName: String?
    var mdnsName: String?
    var ipv6Addresses: [String]
    var workgroup: String?
    var openPorts: [Int]
    var serviceTitle: String?
    var status: Status

    init(
        id: UUID = UUID(),
        ip: String,
        hostname: String? = nil,
        mac: String? = nil,
        vendor: String? = nil,
        vendorStatus: VendorStatus? = nil,
        rttMs: Double? = nil,
        ttl: Int? = nil,
        netbiosName: String? = nil,
        mdnsName: String? = nil,
        ipv6Addresses: [String] = [],
        workgroup: String? = nil,
        openPorts: [Int] = [],
        serviceTitle: String? = nil,
        status: Status = .scanning
    ) {
        self.id = id
        self.ip = ip
        self.hostname = hostname
        self.mac = mac
        self.vendor = vendor
        self.vendorStatus = vendorStatus
        self.rttMs = rttMs
        self.ttl = ttl
        self.netbiosName = netbiosName
        self.mdnsName = mdnsName
        self.ipv6Addresses = ipv6Addresses
        self.workgroup = workgroup
        self.openPorts = openPorts
        self.serviceTitle = serviceTitle
        self.status = status
    }

    var ipNumeric: UInt32 { IPv4.uint32(from: ip) ?? 0 }

    /// Merges a newer partial-result `update` onto `self`, keeping any field
    /// `update` left empty. Used to fold together enrichment events (DNS, ARP,
    /// NetBIOS, port scan, banner probe) that arrive for the same host at
    /// different times — shared by the GUI scan loop (`ScanController`) and the
    /// CLI so the two can't silently diverge on which fields survive a merge.
    func merged(with update: Host) -> Host {
        var merged = self
        if let v = update.hostname { merged.hostname = v }
        if let v = update.mac { merged.mac = v }
        if let status = update.vendorStatus {
            merged.mac = update.mac
            merged.vendor = update.vendor
            merged.vendorStatus = status
        } else if let v = update.vendor { merged.vendor = v }
        if let v = update.rttMs { merged.rttMs = v }
        if let v = update.ttl { merged.ttl = v }
        if let v = update.netbiosName { merged.netbiosName = v }
        if let v = update.mdnsName { merged.mdnsName = v }
        if !update.ipv6Addresses.isEmpty { merged.ipv6Addresses = update.ipv6Addresses }
        if let v = update.workgroup { merged.workgroup = v }
        if let v = update.serviceTitle { merged.serviceTitle = v }
        merged.openPorts = update.openPorts.isEmpty ? merged.openPorts : update.openPorts
        merged.status = update.status
        return merged
    }
}
