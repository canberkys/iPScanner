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
    private var pendingConnections: [NWConnection] = []
    private let resolveQueue = DispatchQueue(
        label: "iPScanner.mdns.resolve",
        attributes: .concurrent
    )

    var isRunning: Bool { !browsers.isEmpty }

    func start() {
        guard browsers.isEmpty else { return }
        for (type, label) in Self.serviceTypes {
            let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: "local.")
            let browser = NWBrowser(for: descriptor, using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    self?.handle(results: results, displayType: label)
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    func stop() {
        for b in browsers { b.cancel() }
        browsers.removeAll()
        for c in pendingConnections { c.cancel() }
        pendingConnections.removeAll()
    }

    func services(for ip: String) -> [ServiceRecord] {
        Array(servicesByIP[ip] ?? []).sorted {
            if $0.displayType == $1.displayType { return $0.name < $1.name }
            return $0.displayType < $1.displayType
        }
    }

    func uniqueServiceTypes(for ip: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for s in services(for: ip) where !seen.contains(s.displayType) {
            seen.insert(s.displayType)
            ordered.append(s.displayType)
        }
        return ordered
    }

    // MARK: - Internals

    private func handle(results: Set<NWBrowser.Result>, displayType: String) {
        for result in results {
            guard case .service(let name, let type, let domain, _) = result.endpoint else { continue }
            resolveService(name: name, type: type, domain: domain, displayType: displayType)
        }
    }

    private func resolveService(name: String, type: String, domain: String, displayType: String) {
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)
        pendingConnections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let path = connection.currentPath,
                   case .hostPort(let host, _) = path.remoteEndpoint,
                   let ip = Self.ipv4String(from: host) {
                    Task { @MainActor in
                        self?.add(
                            record: ServiceRecord(
                                displayType: displayType,
                                serviceType: type,
                                name: name,
                                ip: ip
                            )
                        )
                        self?.dropConnection(connection)
                    }
                }
                connection.cancel()
            case .failed, .cancelled:
                Task { @MainActor in
                    self?.dropConnection(connection)
                }
            default:
                break
            }
        }
        connection.start(queue: resolveQueue)
    }

    private func add(record: ServiceRecord) {
        servicesByIP[record.ip, default: []].insert(record)
    }

    private func dropConnection(_ connection: NWConnection) {
        pendingConnections.removeAll { $0 === connection }
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
