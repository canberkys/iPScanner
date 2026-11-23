import Foundation
import Darwin

enum WakeOnLAN {
    enum WoLError: Error { case invalidMAC, invalidAddress, socketFailed(Int32), sendFailed(Int32) }

    /// Sends one magic packet to each destination and succeeds if at least one send works.
    /// Network.framework cannot set SO_BROADCAST, so this uses a plain UDP socket.
    static func wake(
        mac: String,
        destinations: [String] = broadcastDestinations(),
        port: UInt16 = 9
    ) throws {
        guard let payload = magicPacket(mac: mac) else { throw WoLError.invalidMAC }
        var lastError: WoLError = .invalidAddress
        var sent = false
        for destination in destinations {
            do {
                try send(payload, to: destination, port: port)
                sent = true
            } catch let error as WoLError {
                lastError = error
            }
        }
        if !sent { throw lastError }
    }

    /// 255.255.255.255 leaves through the primary interface only, so each active
    /// Ethernet/Wi-Fi subnet also gets its directed broadcast (e.g. 192.168.1.255).
    /// VPN tunnels are skipped: magic packets only work on the local segment.
    static func broadcastDestinations(interfaces: [NetworkInterfaceInfo] = NetworkInterface.activeInterfaces()) -> [String] {
        var result = ["255.255.255.255"]
        for iface in interfaces where iface.name.hasPrefix("en") || iface.name.hasPrefix("bridge") {
            guard (1...30).contains(iface.netmaskBits), let ip = IPv4.uint32(from: iface.ipv4) else { continue }
            let mask = UInt32.max << (32 - iface.netmaskBits)
            let directed = IPv4.string(from: (ip & mask) | ~mask)
            if !result.contains(directed) { result.append(directed) }
        }
        return result
    }

    static func send(_ payload: Data, to destination: String, port: UInt16) throws {
        guard IPv4.uint32(from: destination) != nil else { throw WoLError.invalidAddress }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw WoLError.socketFailed(errno) }
        defer { close(fd) }

        var enable: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw WoLError.socketFailed(errno)
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, destination, &addr.sin_addr) == 1 else { throw WoLError.invalidAddress }

        let written = payload.withUnsafeBytes { bytes in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard written == payload.count else { throw WoLError.sendFailed(errno) }
    }

    static func wakeAll(macs: [String]) async -> (sent: Int, failed: Int) {
        let unique = Array(Set(macs))
        return await Task.detached(priority: .userInitiated) {
            let destinations = broadcastDestinations()
            var sent = 0, failed = 0
            for mac in unique {
                do { try wake(mac: mac, destinations: destinations); sent += 1 } catch { failed += 1 }
            }
            return (sent, failed)
        }.value
    }

    static func magicPacket(mac: String) -> Data? {
        guard let address = MACAddress(mac), address.kind == .universal || address.kind == .local else { return nil }
        var payload = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { payload.append(contentsOf: address.bytes) }
        return payload
    }
}
