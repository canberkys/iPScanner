import Foundation
import Darwin

struct NetworkInterfaceInfo: Hashable {
    let name: String
    let ipv4: String
    let netmaskBits: Int
}

enum NetworkInterface {
    static func activeInterfaces() -> [NetworkInterfaceInfo] {
        var results: [NetworkInterfaceInfo] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return results }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }
            let entry = ptr.pointee
            let flags = Int32(entry.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addrPtr = entry.ifa_addr,
                  addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let name = String(cString: entry.ifa_name)

            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = getnameinfo(addrPtr,
                                 socklen_t(MemoryLayout<sockaddr_in>.size),
                                 &hostBuf, socklen_t(NI_MAXHOST),
                                 nil, 0, NI_NUMERICHOST)
            guard rc == 0 else { continue }
            let ipv4 = String(cString: hostBuf)
            if ipv4.hasPrefix("169.254.") { continue }

            guard let maskPtr = entry.ifa_netmask else { continue }
            let maskBE = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            let bits = UInt32(bigEndian: maskBE).nonzeroBitCount

            results.append(NetworkInterfaceInfo(name: name, ipv4: ipv4, netmaskBits: bits))
        }
        return results
    }

    static func defaultSubnet() -> String? {
        let preferred =
            scannableInterfaces().first(where: { $0.name == "en0" }) ??
            scannableInterfaces().first(where: { $0.name == "en1" }) ??
            scannableInterfaces().first
        return preferred.flatMap(subnet(from:))
    }

    /// Active interfaces filtered to ones likely to host a useful subnet for scanning.
    /// Excludes Apple Wireless Direct Link, link-local helpers, /31, /32.
    static func scannableInterfaces() -> [NetworkInterfaceInfo] {
        let nameAllow: [String] = ["en", "bridge", "utun"]
        return activeInterfaces().filter { iface in
            guard nameAllow.contains(where: { iface.name.hasPrefix($0) }) else { return false }
            return iface.netmaskBits >= 16 && iface.netmaskBits <= 30
        }
    }

    static func subnet(from info: NetworkInterfaceInfo) -> String? {
        guard let ipInt = IPv4.uint32(from: info.ipv4) else { return nil }
        let mask: UInt32 = info.netmaskBits == 0 ? 0 : UInt32.max << (32 - info.netmaskBits)
        let network = ipInt & mask
        return "\(IPv4.string(from: network))/\(info.netmaskBits)"
    }
}
