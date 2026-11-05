import Foundation
import Network
import Observation

@Observable
@MainActor
final class MDNSDiscovery {
    struct ServiceRecord: Hashable {
        let displayType: String
        let serviceType: String
        let name: String
        let ip: String
        var txt: [String: String] = [:]
    }

    static let serviceTypes: [(type: String, label: String)] = [
        ("_airplay._tcp", "AirPlay"),
        ("_raop._tcp", "AirPlay Audio"),
        ("_googlecast._tcp", "Chromecast"),
        ("_companion-link._tcp", "Apple Companion"),
        ("_homekit._tcp", "HomeKit"),
        ("_hap._tcp", "HomeKit"),
        ("_smb._tcp", "SMB"),
        ("_afpovertcp._tcp", "AFP"),
        ("_nfs._tcp", "NFS"),
        ("_ssh._tcp", "SSH"),
        ("_rfb._tcp", "VNC"),
        ("_workstation._tcp", "Workstation"),
        ("_http._tcp", "HTTP"),
        ("_https._tcp", "HTTPS"),
        ("_ipp._tcp", "IPP"),
        ("_printer._tcp", "Printer"),
        ("_pdl-datastream._tcp", "Print"),
        ("_device-info._tcp", "Device Info")
    ]

    private(set) var servicesByIP: [String: Set<ServiceRecord>] = [:]
    private var browsers: [NWBrowser] = []
    private var connections: [String: NWConnection] = [:]
    private var inventory = BonjourInventory()
    private var monitor: NWPathMonitor?
    private var networkFingerprint: String?
    private var generation = UUID()
    private let resolveQueue = DispatchQueue(label: "iPScanner.mdns", attributes: .concurrent)
    var isRunning: Bool { !browsers.isEmpty }

    func start() {
        guard !isRunning else { return }
        let run = UUID(); generation = run
        for (type, label) in Self.serviceTypes {
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    guard let self, self.generation == run else { return }
                    self.handle(results: results, type: type, displayType: label, run: run)
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
        let monitor = NWPathMonitor(); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self, self.generation == run else { return }
                let addresses = NetworkInterface.scannableInterfaces().map { "\($0.name):\($0.ipv4)/\($0.netmaskBits)" }.sorted().joined(separator: ",")
                let fingerprint = "\(path.status):\(addresses)"
                if let previous = self.networkFingerprint, previous != fingerprint {
                    self.stop(); self.start()
                } else { self.networkFingerprint = fingerprint }
            }
        }
        monitor.start(queue: resolveQueue)
    }

    func stop() {
        generation = UUID()
        for browser in browsers { browser.cancel() }
        browsers.removeAll()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        inventory = BonjourInventory()
        servicesByIP = [:]
        monitor?.cancel(); monitor = nil; networkFingerprint = nil
    }

    func services(for ip: String) -> [ServiceRecord] {
        Array(servicesByIP[ip] ?? []).sorted { ($0.displayType, $0.name) < ($1.displayType, $1.name) }
    }
    /// Best device name advertised over Bonjour for `ip`, if any.
    func deviceName(for ip: String) -> String? { Self.deviceName(from: services(for: ip)) }

    /// Picks a device name from Bonjour instance names. `_workstation` carries
    /// the real hostname ("name [mac]"); other services carry friendly names.
    nonisolated static func deviceName(from records: [ServiceRecord]) -> String? {
        let priority = ["_workstation._tcp", "_device-info._tcp", "_companion-link._tcp", "_airplay._tcp",
                        "_smb._tcp", "_ssh._tcp", "_rfb._tcp", "_afpovertcp._tcp"]
        for type in priority {
            for record in records.sorted(by: { $0.name < $1.name }) where record.serviceType == type {
                var name = record.name
                if let bracket = name.range(of: " [") { name = String(name[..<bracket.lowerBound]) }
                name = name.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }
    func identification(for ip: String) -> String? { Self.identification(from: services(for: ip)) }

    /// LanScan-style "Identification": the device model and printer name a host announces.
    nonisolated static func identification(from records: [ServiceRecord]) -> String? {
        var parts: [String] = []
        func add(_ value: String?) {
            let v = (value ?? "").trimmingCharacters(in: .whitespaces)
            if !v.isEmpty, !parts.contains(v) { parts.append(v) }
        }
        let sorted = records.sorted { $0.name < $1.name }
        for r in sorted where r.serviceType == "_device-info._tcp" || r.serviceType == "_airplay._tcp" { add(r.txt["model"]) }
        for r in sorted where r.serviceType == "_raop._tcp" { add(r.txt["am"]) }
        for r in sorted where ["_ipp._tcp", "_printer._tcp", "_pdl-datastream._tcp"].contains(r.serviceType) {
            var name = r.name
            if let bracket = name.range(of: " [") { name = String(name[..<bracket.lowerBound]) }
            add(r.txt["ty"] ?? name)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
    func uniqueServiceTypes(for ip: String) -> [String] { Array(Set(services(for: ip).map(\.displayType))).sorted() }

    private func handle(results: Set<NWBrowser.Result>, type: String, displayType: String, run: UUID) {
        var endpoints: [String: (NWEndpoint, String, [String: String])] = [:]
        for result in results {
            guard case .service(let name, _, let domain, let interface) = result.endpoint else { continue }
            let id = "\(type)|\(domain)|\(name)|\(interface?.index ?? 0)"
            var txt: [String: String] = [:]
            if case .bonjour(let record) = result.metadata { txt = record.dictionary }
            endpoints[id] = (result.endpoint, name, txt)
        }
        let removed = inventory.reconcile(ids: Set(endpoints.keys), type: type)
        for id in removed { connections.removeValue(forKey: id)?.cancel() }
        rebuild()
        for (id, value) in endpoints where connections[id] == nil && inventory.records[id] == nil {
            guard let token = inventory.tokens[id] else { continue }
            // Force IPv4: the service endpoint otherwise resolves to IPv6 for most remote
            // hosts, and the scan list is keyed by IPv4 address.
            let parameters = NWParameters.tcp
            if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ipOptions.version = .v4
            }
            let connection = NWConnection(to: value.0, using: parameters)
            connections[id] = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let connection else { return }
                switch state {
                case .ready:
                    let host: NWEndpoint.Host?
                    if let path = connection.currentPath, case .hostPort(let remote, _) = path.remoteEndpoint { host = remote } else { host = nil }
                    let ip = host.flatMap(Self.ipv4String)
                    Task { @MainActor in
                        guard let self, self.generation == run else { return }
                        if let ip { self.inventory.accept(.init(displayType: displayType, serviceType: type, name: value.1, ip: ip, txt: value.2), id: id, token: token) }
                        self.rebuild()
                        if self.connections[id] === connection { self.connections.removeValue(forKey: id) }
                        connection.cancel()
                    }
                case .failed, .cancelled:
                    Task { @MainActor in
                        guard let self, self.generation == run else { return }
                        if self.connections[id] === connection { self.connections.removeValue(forKey: id) }
                    }
                default: break
                }
            }
            connection.start(queue: resolveQueue)
            Task { @MainActor [weak self, weak connection] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, let connection, self.generation == run, self.connections[id] === connection else { return }
                self.connections.removeValue(forKey: id); connection.cancel()
            }
        }
    }
    private func rebuild() {
        servicesByIP = Dictionary(grouping: inventory.records.values, by: \.ip).mapValues(Set.init)
    }

    nonisolated private static func ipv4String(from host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let addr):
            let bytes = addr.rawValue
            guard bytes.count == 4 else { return nil }
            return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
        default:
            return nil
        }
    }
}


// Reconciles complete browser snapshots and rejects a late resolution after removal.
struct BonjourInventory {
    private(set) var tokens: [String: UUID] = [:]
    private(set) var records: [String: MDNSDiscovery.ServiceRecord] = [:]
    mutating func reconcile(ids: Set<String>, type: String) -> Set<String> {
        let previous = Set(tokens.keys.filter { $0.hasPrefix(type + "|") })
        let removed = previous.subtracting(ids)
        for id in removed { tokens.removeValue(forKey: id); records.removeValue(forKey: id) }
        for id in ids where tokens[id] == nil { tokens[id] = UUID() }
        return removed
    }
    mutating func accept(_ record: MDNSDiscovery.ServiceRecord, id: String, token: UUID) {
        guard tokens[id] == token else { return }
        records[id] = record
    }
}
