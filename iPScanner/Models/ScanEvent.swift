import Foundation

enum ScanEvent: Sendable {
    case phase(ScanPhase)
    case progress(scanned: Int, total: Int)
    case host(Host)
    case warning(ScanWarning)
    case done
}

enum ScanWarning: Sendable, Hashable {
    /// Empty results can reflect routing, cache state, or OS privacy restrictions.
    case arpFailed(String)
    case arpEmpty
    /// At least one banner fetch (HTTP title / SSH greeting) failed.
    case bannerFetchFailures(count: Int)
    /// /sbin/ping could not be started, so ICMP results are missing.
    case pingUnavailable(String)

    var label: String {
        switch self {
        case .arpFailed(let message): return message
        case .arpEmpty:
            return "MAC addresses unavailable (ARP table empty)"
        case .bannerFetchFailures(let n):
            return "\(n) banner fetch\(n == 1 ? "" : "es") failed"
        case .pingUnavailable:
            return "ICMP ping could not run"
        }
    }

    var detail: String {
        switch self {
        case .arpFailed(let message): return message
        case .arpEmpty:
            if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
                return "macOS returned no MAC records. macOS 27 may require the Network Topology Observation capability in a signed, provisioned app. Local network permission alone may not provide MAC access. Routed devices also have no local MAC record."
            }
            return "No MAC addresses returned from arp(8). Hosts behind a router or first-time scans on a quiet network may take a second pass."
        case .bannerFetchFailures:
            return "HTTP title or SSH greeting could not be read. Banners are best-effort enrichment and don't affect host discovery."
        case .pingUnavailable(let message):
            return "\(message). Hosts were checked with TCP probes only (when the profile allows it), so devices that answer only to ping are reported as unresponsive."
        }
    }
}

extension Host: @unchecked Sendable {}

enum ScanPhase: String, Sendable {
    case discovery = "Discovering devices"
    case enrichment = "Resolving device details"
    case ports = "Scanning ports"
    case banners = "Reading service banners"
}
