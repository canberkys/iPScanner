import Darwin
import Foundation

/// Sends ICMP echo requests to many addresses from one unprivileged datagram
/// socket and collects the replies, instead of launching `/sbin/ping` once per
/// address. Process start-up and per-process timeouts dominated scan time on /22
/// ranges; a single socket keeps all requests in flight at once.
enum ICMPSweeper {
    struct Reply: Sendable, Equatable {
        let rttMs: Double
        let ttl: Int?
    }

    /// Returns replies keyed by IPv4 address, or nil when the socket could not be
    /// created (the caller then falls back to per-address pings).
    static func sweep(_ addresses: [String], waitMs: Int = 900) async -> [String: Reply]? {
        let token = CancelToken()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[String: Reply]?, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: run(addresses, waitMs: waitMs, token: token))
                }
            }
        } onCancel: { token.cancel() }
    }

    private final class CancelToken: @unchecked Sendable {
        private let lock = NSLock(); private var flag = false
        func cancel() { lock.lock(); flag = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }

    private static func run(_ addresses: [String], waitMs: Int, token: CancelToken) -> [String: Reply]? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var buf = Int32(1 << 20)
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &buf, socklen_t(MemoryLayout<Int32>.size))
        var sendBuf = Int32(1 << 20)
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sendBuf, socklen_t(MemoryLayout<Int32>.size))

        let wanted = Set(addresses)
        let identifier = UInt16.random(in: 1...UInt16.max)
        var sentAt: [String: DispatchTime] = [:]
        var replies: [String: Reply] = [:]
        var recvBuffer = [UInt8](repeating: 0, count: 2048)

        func drain() {
            while true {
                var from = sockaddr_in()
                var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, &recvBuffer, recvBuffer.count, 0, $0, &len)
                    }
                }
                if n <= 0 { return }
                var addr = from.sin_addr
                var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &addr, &text, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
                let ip = String(cString: text)
                guard wanted.contains(ip), replies[ip] == nil,
                      let parsed = parseReply(Array(recvBuffer[0..<n])) else { continue }
                let rtt = sentAt[ip].map { Double(DispatchTime.now().uptimeNanoseconds - $0.uptimeNanoseconds) / 1_000_000 } ?? 0
                replies[ip] = Reply(rttMs: rtt, ttl: parsed.ttl)
            }
        }

        for (index, ip) in addresses.enumerated() {
            if token.isCancelled { return replies }
            var dest = sockaddr_in()
            dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            dest.sin_family = sa_family_t(AF_INET)
            guard inet_pton(AF_INET, ip, &dest.sin_addr) == 1 else { continue }
            let packet = buildEchoRequest(identifier: identifier, sequence: UInt16(truncatingIfNeeded: index))
            sentAt[ip] = .now()
            var attempts = 0
            while attempts < 50 {
                let sent = packet.withUnsafeBytes { raw in
                    withUnsafePointer(to: &dest) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(fd, raw.baseAddress, raw.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                if sent >= 0 { break }
                if errno == EAGAIN || errno == ENOBUFS { drain(); usleep(1000); attempts += 1 } else { break }
            }
            if index % 32 == 31 { drain() }
        }

        let deadline = DispatchTime.now() + .milliseconds(waitMs)
        while DispatchTime.now() < deadline, !token.isCancelled, replies.count < wanted.count {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            _ = poll(&pfd, 1, 50)
            drain()
        }
        return replies
    }

    // MARK: - Wire format

    /// ICMP echo request (type 8) with an 8-byte payload and a valid checksum.
    static func buildEchoRequest(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var p: [UInt8] = [8, 0, 0, 0,
                          UInt8(identifier >> 8), UInt8(identifier & 0xFF),
                          UInt8(sequence >> 8), UInt8(sequence & 0xFF)]
        p.append(contentsOf: Array("iPScanne".utf8))
        let sum = checksum(p)
        p[2] = UInt8(sum >> 8); p[3] = UInt8(sum & 0xFF)
        return p
    }

    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count { sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]); i += 2 }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(sum & 0xFFFF)
    }

    /// Parses an echo reply (type 0). macOS includes the IP header on datagram ICMP
    /// sockets, so the TTL is read from it when present.
    static func parseReply(_ data: [UInt8]) -> (ttl: Int?, sequence: UInt16)? {
        var offset = 0
        var ttl: Int?
        if let first = data.first, first >> 4 == 4 {
            offset = Int(first & 0x0F) * 4
            if data.count > 8 { ttl = Int(data[8]) }
        }
        guard data.count >= offset + 8, data[offset] == 0 else { return nil }
        return (ttl, UInt16(data[offset + 6]) << 8 | UInt16(data[offset + 7]))
    }
}
