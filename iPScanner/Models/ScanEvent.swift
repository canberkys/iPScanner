import Foundation

enum ScanEvent: Sendable {
    case progress(scanned: Int, total: Int)
    case host(Host)
    case warning(ScanWarning)
    case done
}

enum ScanWarning: Sendable, Hashable {
    /// ARP returned no entries while at least one host was alive — usually an L3
    /// boundary, a stale cache, or no L2 traffic since boot.
    case arpEmpty
    /// At least one banner fetch (HTTP title / SSH greeting) failed.
    case bannerFetchFailures(count: Int)

    var label: String {
        switch self {
        case .arpEmpty:
            return "MAC addresses unavailable (ARP table empty)"
        case .bannerFetchFailures(let n):
            return "\(n) banner fetch\(n == 1 ? "" : "es") failed"
        }
    }

    var detail: String {
        switch self {
        case .arpEmpty:
            return "No MAC addresses returned from arp(8). Hosts behind a router or first-time scans on a quiet network may take a second pass."
        case .bannerFetchFailures:
            return "HTTP title or SSH greeting could not be read. Banners are best-effort enrichment and don't affect host discovery."
        }
    }
}

extension Host: @unchecked Sendable {}
