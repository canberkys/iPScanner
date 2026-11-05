import Foundation

/// Finds the IPv6 addresses of devices on the local link. One multicast ping to
/// `ff02::1` makes every IPv6 host answer, which fills the neighbor cache; the cache
/// (`ndp -an`) maps each address to a MAC, so it can be matched to a scanned IPv4 host.
enum IPv6Neighbors {
    static func discover(interfaces: [String]) async -> [String: [String]] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String: [String]], Never>) in
            DispatchQueue.global(qos: .utility).async {
                for name in interfaces where name.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil {
                    _ = run("/sbin/ping6", ["-c", "2", "-i", "0.4", "ff02::1%\(name)"], timeout: 2.5)
                }
                continuation.resume(returning: parse(run("/usr/sbin/ndp", ["-an"], timeout: 3)))
            }
        }
    }

    /// MAC (canonical) → IPv6 addresses, from `ndp -an` output.
    static func parse(_ output: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 3, !line.contains("(incomplete)"),
                  let mac = MACAddress(String(fields[1])) else { continue }
            let address = String(fields[0]).split(separator: "%").first.map(String.init) ?? String(fields[0])
            guard address.contains(":"), !(result[mac.canonical] ?? []).contains(address) else { continue }
            result[mac.canonical, default: []].append(address)
        }
        return result.mapValues { $0.sorted() }
    }

    /// Link-local (fe80::/10) and unique-local (fc00::/7) addresses are "local"; the rest are global.
    static func isLocal(_ address: String) -> Bool {
        let a = address.lowercased()
        return a.hasPrefix("fe8") || a.hasPrefix("fe9") || a.hasPrefix("fea") || a.hasPrefix("feb")
            || a.hasPrefix("fc") || a.hasPrefix("fd")
    }

    /// One address, plus a count of the others ("Multiple" in the tooltip).
    static func summary(_ addresses: [String]) -> String? {
        guard let first = addresses.first else { return nil }
        return addresses.count > 1 ? "\(first) (+\(addresses.count - 1))" : first
    }

    private static func run(_ path: String, _ arguments: [String], timeout: Double) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        guard (try? process.run()) != nil else { return "" }
        if done.wait(timeout: .now() + timeout) == .timedOut { process.terminate() }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
