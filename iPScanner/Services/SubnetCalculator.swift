import Foundation

/// Pure computation. Given a CIDR, derive the network address, broadcast,
/// usable host range, count, and dotted netmask. Uses the same `IPv4` helpers
/// as `ScanRange` so the math stays consistent across the app.
enum SubnetCalculator {
    struct Summary: Equatable {
        let cidr: String
        let prefix: Int
        let network: String
        let broadcast: String
        let firstHost: String?
        let lastHost: String?
        let hostCount: Int
        let netmask: String
        let wildcard: String
    }

    static func summarize(_ input: String) -> Summary? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard let slash = trimmed.firstIndex(of: "/") else { return nil }

        let ipPart = String(trimmed[..<slash])
        let prefixPart = String(trimmed[trimmed.index(after: slash)...])
        guard let prefix = Int(prefixPart), (0...32).contains(prefix) else { return nil }
        guard let ipInt = IPv4.uint32(from: ipPart) else { return nil }

        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
        let network = ipInt & mask
        let broadcast = network | ~mask
        let totalAddresses = Int(broadcast) - Int(network) + 1

        // Usable host range:
        //   /32: single address, no broadcast / network distinction
        //   /31: RFC 3021 — both addresses are usable
        //   /N (N <= 30): exclude network and broadcast
        let firstHost: String?
        let lastHost: String?
        let hostCount: Int
        switch prefix {
        case 32:
            firstHost = IPv4.string(from: network)
            lastHost = firstHost
            hostCount = 1
        case 31:
            firstHost = IPv4.string(from: network)
            lastHost = IPv4.string(from: broadcast)
            hostCount = 2
        default:
            firstHost = network &+ 1 <= broadcast &- 1 ? IPv4.string(from: network &+ 1) : nil
            lastHost = network &+ 1 <= broadcast &- 1 ? IPv4.string(from: broadcast &- 1) : nil
            hostCount = max(0, totalAddresses - 2)
        }

        return Summary(
            cidr: trimmed,
            prefix: prefix,
            network: IPv4.string(from: network),
            broadcast: IPv4.string(from: broadcast),
            firstHost: firstHost,
            lastHost: lastHost,
            hostCount: hostCount,
            netmask: IPv4.string(from: mask),
            wildcard: IPv4.string(from: ~mask)
        )
    }
}
