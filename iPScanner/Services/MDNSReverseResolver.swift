import Foundation
import Network

/// Reverse mDNS lookup: asks a host directly (UDP 5353) for the name it
/// announces for its own IPv4 address, e.g. `Katherines-MacBook-Air-2.local`.
/// Unlike browsing Bonjour services, this works for devices that advertise no
/// service types, and does not depend on the host answering ping.
enum MDNSReverseResolver {
    static let timeoutMs = 1200

    /// One retry: phones and tablets in power-save sometimes miss the first query.
    static func resolveWithRetry(_ ip: String) async -> String? {
        if let name = await resolve(ip) { return name }
        guard !Task.isCancelled else { return nil }
        return await resolve(ip)
    }

    static func resolve(_ ip: String) async -> String? {
        guard let query = buildQuery(for: ip), let port = NWEndpoint.Port(rawValue: 5353) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let queue = DispatchQueue.global(qos: .userInitiated)
            let connection = NWConnection(host: NWEndpoint.Host(ip), port: port, using: .udp)
            let state = ResumeOnce()
            let timeoutWork = DispatchWorkItem {
                connection.cancel()
                state.fire { continuation.resume(returning: nil) }
            }
            queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timeoutWork)
            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    connection.send(content: query, completion: .contentProcessed { _ in })
                    connection.receiveMessage { data, _, _, _ in
                        timeoutWork.cancel()
                        let name = data.flatMap { parseResponse($0) }
                        connection.cancel()
                        state.fire { continuation.resume(returning: name) }
                    }
                case .failed, .cancelled:
                    timeoutWork.cancel()
                    state.fire { continuation.resume(returning: nil) }
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    // MARK: - Wire format

    /// PTR query for `d.c.b.a.in-addr.arpa`.
    static func buildQuery(for ip: String) -> Data? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else { return nil }
        var data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in parts.reversed() + ["in-addr", "arpa"] {
            data.append(UInt8(label.utf8.count)); data.append(contentsOf: Array(label.utf8))
        }
        data.append(0x00)
        data.append(contentsOf: [0x00, 0x0C, 0x00, 0x01])  // PTR, IN
        return data
    }

    /// Returns the first PTR target in the answer section, without the `.local` suffix.
    static func parseResponse(_ data: Data) -> String? {
        let b = Array(data)
        guard b.count >= 12 else { return nil }
        var i = 12
        let qd = Int(b[4]) << 8 | Int(b[5]), an = Int(b[6]) << 8 | Int(b[7])
        for _ in 0..<qd {
            guard readName(b, &i) != nil, i + 4 <= b.count else { return nil }
            i += 4
        }
        for _ in 0..<an {
            guard readName(b, &i) != nil, i + 10 <= b.count else { return nil }
            let type = Int(b[i]) << 8 | Int(b[i + 1])
            let rdlen = Int(b[i + 8]) << 8 | Int(b[i + 9])
            i += 10
            guard i + rdlen <= b.count else { return nil }
            if type == 12 {
                var j = i
                guard let name = readName(b, &j) else { return nil }
                return clean(name)
            }
            i += rdlen
        }
        return nil
    }

    static func clean(_ name: String) -> String? {
        var n = name
        if n.lowercased().hasSuffix(".local") { n = String(n.dropLast(6)) }
        n = n.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        // Some stacks answer with a placeholder instead of a real name.
        if n.isEmpty || n.caseInsensitiveCompare("MDNSHOSTNAME") == .orderedSame { return nil }
        return n
    }

    /// Reads a possibly-compressed DNS name starting at `i`, advancing `i` past it.
    private static func readName(_ b: [UInt8], _ i: inout Int) -> String? {
        var labels: [String] = []
        var pos = i
        var jumped = false
        var hops = 0
        while pos < b.count {
            let len = Int(b[pos])
            if len == 0 { pos += 1; if !jumped { i = pos }; return labels.joined(separator: ".") }
            if len & 0xC0 == 0xC0 {
                guard pos + 1 < b.count, hops < 10 else { return nil }
                let target = (len & 0x3F) << 8 | Int(b[pos + 1])
                if !jumped { i = pos + 2 }
                jumped = true; hops += 1; pos = target
                continue
            }
            guard pos + 1 + len <= b.count else { return nil }
            labels.append(String(decoding: b[(pos + 1)..<(pos + 1 + len)], as: UTF8.self))
            pos += 1 + len
        }
        return nil
    }
}
