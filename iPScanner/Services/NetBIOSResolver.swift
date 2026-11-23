import Foundation
import Network

/// NetBIOS Name Service (RFC 1002) resolver.
/// Sends a wildcard NBSTAT query to UDP 137 and parses the node-status response,
/// extracting the Windows-style computer name and workgroup / domain.
///
/// Useful on enterprise networks where DNS records lag and `/usr/sbin/arp` plus
/// the OUI registry are not enough to identify a Windows host.
enum NetBIOSResolver {
    struct Result: Sendable, Equatable {
        let computerName: String?
        let workgroup: String?
    }

    static let timeoutMs = 800

    static func resolve(_ ip: String) async -> Result? {
        guard !Task.isCancelled, let port = NWEndpoint.Port(rawValue: 137) else { return nil }
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: port, using: .udp)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Result?, Never>) in
                let queue = DispatchQueue.global(qos: .userInitiated)
                let state = ResumeOnce()
                let query = buildQuery(transactionID: UInt16.random(in: 0...UInt16.max))

                // Every exit path cancels the connection so its UDP socket is released.
                let finish: @Sendable (Result?) -> Void = { value in
                    connection.cancel()
                    state.fire { continuation.resume(returning: value) }
                }
                queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) { finish(nil) }

                connection.stateUpdateHandler = { newState in
                    switch newState {
                    case .ready:
                        connection.send(content: query, completion: .contentProcessed { _ in })
                        connection.receiveMessage { data, _, _, _ in
                            finish(data.flatMap { parseResponse($0) })
                        }
                    case .failed, .cancelled:
                        finish(nil)
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: { connection.cancel() }
    }

    // MARK: - Wire format

    /// Builds an NBSTAT query packet (50 bytes) for the wildcard name `*`.
    static func buildQuery(transactionID: UInt16) -> Data {
        var data = Data()
        data.append(UInt8(transactionID >> 8))
        data.append(UInt8(transactionID & 0xFF))
        data.append(contentsOf: [0x00, 0x00])  // Flags: standard query, not recursive
        data.append(contentsOf: [0x00, 0x01])  // QDCOUNT = 1
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])  // ANCOUNT, NSCOUNT, ARCOUNT = 0

        // Encoded wildcard "*" name. RFC 1002 nibble encoding: each input byte X
        // becomes two bytes (high_nibble + 'A', low_nibble + 'A'). The wildcard
        // is "*" followed by 15 NUL bytes.
        data.append(0x20)  // length of the encoded name (32 bytes)
        let wildcardEncoded = "CK" + String(repeating: "AA", count: 15)
        data.append(contentsOf: Array(wildcardEncoded.utf8))
        data.append(0x00)  // null root terminator

        data.append(contentsOf: [0x00, 0x21])  // QTYPE = NBSTAT (33)
        data.append(contentsOf: [0x00, 0x01])  // QCLASS = IN
        return data
    }

    /// Parses an NBSTAT response. Returns nil for malformed packets.
    static func parseResponse(_ data: Data) -> Result? {
        guard data.count >= 12 else { return nil }

        let bytes = Array(data)
        var i = 12  // skip the 12-byte header

        // Real Windows/Samba NODE STATUS RESPONSEs typically have QDCOUNT = 0 (the
        // question isn't echoed back) even though our own query sets QDCOUNT = 1 —
        // only skip a question section if the response actually says it has one.
        let qdCount = Int(bytes[4]) << 8 | Int(bytes[5])
        for _ in 0..<qdCount {
            guard skipName(in: bytes, from: &i) else { return nil }
            i += 4  // QTYPE + QCLASS
        }

        // Answer record begins. Skip its name.
        guard skipName(in: bytes, from: &i) else { return nil }
        // TYPE(2) + CLASS(2) + TTL(4) + RDLENGTH(2)
        guard i + 10 <= bytes.count else { return nil }
        i += 10

        // NBSTAT RDATA: 1 byte name count, then per-name records (18 bytes each).
        guard i < bytes.count else { return nil }
        let numNames = Int(bytes[i]); i += 1

        var computerName: String?
        var workgroup: String?

        for _ in 0..<numNames {
            guard i + 18 <= bytes.count else { return nil }
            let nameSlice = Array(bytes[i..<(i + 15)])
            let typeByte = bytes[i + 15]
            let flagsHi  = bytes[i + 16]
            let isGroup  = (flagsHi & 0x80) != 0
            i += 18

            let name = String(bytes: nameSlice, encoding: .ascii)?
                .trimmingCharacters(in: CharacterSet(charactersIn: " \0")) ?? ""
            guard !name.isEmpty else { continue }

            switch typeByte {
            case 0x00:
                if isGroup {
                    if workgroup == nil { workgroup = name }
                } else {
                    if computerName == nil { computerName = name }
                }
            case 0x1B, 0x1C:
                if workgroup == nil { workgroup = name }
            default:
                break
            }
        }

        if computerName == nil && workgroup == nil { return nil }
        return Result(computerName: computerName, workgroup: workgroup)
    }

    /// Advances `i` past a DNS-style name in `bytes`. Handles both length-prefixed
    /// labels (until a 0x00 root) and 2-byte compression pointers (0xC0 prefix).
    /// Returns false if the name is malformed / runs off the end.
    private static func skipName(in bytes: [UInt8], from i: inout Int) -> Bool {
        while i < bytes.count {
            let len = bytes[i]
            if len == 0 { i += 1; return true }
            if (len & 0xC0) == 0xC0 {
                guard i + 2 <= bytes.count else { return false }
                i += 2
                return true
            }
            let next = i + 1 + Int(len)
            guard next <= bytes.count else { return false }
            i = next
        }
        return false
    }
}
