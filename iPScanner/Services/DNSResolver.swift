import Foundation
import Darwin

enum DNSResolver {
    private static let queue = DispatchQueue(
        label: "iPScanner.dns",
        qos: .utility,
        attributes: .concurrent
    )

    static func reverseLookup(_ ip: String, timeout: Duration = .seconds(1)) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await rawLookup(ip) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func rawLookup(_ ip: String) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            queue.async {
                var sin = sockaddr_in()
                sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                sin.sin_family = sa_family_t(AF_INET)
                guard inet_pton(AF_INET, ip, &sin.sin_addr) == 1 else {
                    continuation.resume(returning: nil)
                    return
                }

                var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let rc = withUnsafePointer(to: &sin) { ptr -> Int32 in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        getnameinfo(sockaddrPtr,
                                    socklen_t(MemoryLayout<sockaddr_in>.size),
                                    &hostBuf, socklen_t(NI_MAXHOST),
                                    nil, 0, NI_NAMEREQD)
                    }
                }
                if rc == 0 {
                    let host = String(cString: hostBuf)
                    continuation.resume(returning: host.isEmpty ? nil : host)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
