import Foundation

protocol NetworkScanning: Sendable {
    func scan(_ range: ScanRange) -> AsyncStream<ScanEvent>
}

struct DiscoverResult: Sendable, Hashable {
    let rttMs: Double
    /// Only populated for ICMP responses. TCP fallback probes don't expose a useful TTL.
    let ttl: Int?
}

struct NetworkScanner: NetworkScanning {
    static let pingConcurrency = 32
    static let enrichConcurrency = 16
    static let pingTimeoutMs = 800
    static let tcpFallbackPorts = [445, 80, 443, 22, 3389]
    static let tcpFallbackTimeoutMs = 400

    let profile: ScanProfile

    init(profile: ScanProfile = .standard) {
        self.profile = profile
    }

    func scan(_ range: ScanRange) -> AsyncStream<ScanEvent> {
        scan(addresses: range.addresses)
    }

    func scan(addresses: [String]) -> AsyncStream<ScanEvent> {
        let useTCPFallback = profile.useTCPFallback
        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await Self.run(
                    addresses: addresses,
                    useTCPFallback: useTCPFallback,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func run(
        addresses: [String],
        useTCPFallback: Bool,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        let total = addresses.count
        continuation.yield(.progress(scanned: 0, total: total))

        // --- Phase 1: discover (ping → TCP fallback) with bounded concurrency ---
        // Always yield dead hosts so the UI can filter on demand without re-scanning.
        var alive: [(ip: String, rtt: Double, ttl: Int?)] = []
        var scanned = 0

        await withTaskGroup(of: (String, DiscoverResult?).self) { group in
            var iter = addresses.makeIterator()
            for _ in 0..<min(pingConcurrency, addresses.count) {
                guard let ip = iter.next() else { break }
                group.addTask { (ip, await Self.discover(ip, useTCPFallback: useTCPFallback)) }
            }

            while let (ip, result) = await group.next() {
                scanned += 1
                continuation.yield(.progress(scanned: scanned, total: total))
                if let result = result {
                    alive.append((ip, result.rttMs, result.ttl))
                    continuation.yield(.host(Host(ip: ip, rttMs: result.rttMs, ttl: result.ttl, status: .alive)))
                } else {
                    continuation.yield(.host(Host(ip: ip, status: .dead)))
                }
                if Task.isCancelled { break }
                if let next = iter.next() {
                    group.addTask { (next, await Self.discover(next, useTCPFallback: useTCPFallback)) }
                }
            }
            if Task.isCancelled { group.cancelAll() }
        }

        if Task.isCancelled {
            continuation.yield(.done)
            continuation.finish()
            return
        }

        // --- ARP grace ---
        try? await Task.sleep(for: .milliseconds(200))
        let arpTable = await ARPLookup.table()
        if arpTable.isEmpty, !alive.isEmpty {
            continuation.yield(.warning(.arpEmpty))
        }
        let oui = OUILookup.shared

        // --- Phase 2: enrich (DNS + MAC + Vendor) per alive host ---
        await withTaskGroup(of: Host.self) { group in
            var iter = alive.makeIterator()

            func enqueue(_ entry: (ip: String, rtt: Double, ttl: Int?)) {
                let mac = arpTable[entry.ip]
                let vendor = mac.flatMap { oui.vendor(forMAC: $0) }
                group.addTask {
                    let hostname = await DNSResolver.reverseLookup(entry.ip)
                    return Host(
                        ip: entry.ip,
                        hostname: hostname,
                        mac: mac,
                        vendor: vendor,
                        rttMs: entry.rtt,
                        ttl: entry.ttl,
                        status: .alive
                    )
                }
            }

            for _ in 0..<min(enrichConcurrency, alive.count) {
                guard let entry = iter.next() else { break }
                enqueue(entry)
            }

            while let host = await group.next() {
                continuation.yield(.host(host))
                if Task.isCancelled { break }
                if let next = iter.next() {
                    enqueue(next)
                }
            }
            if Task.isCancelled { group.cancelAll() }
        }

        continuation.yield(.done)
        continuation.finish()
    }

    // MARK: - discover (ping with TCP fallback)

    /// Returns RTT and (when ICMP succeeded) TTL if the host responded.
    static func discover(_ ip: String, useTCPFallback: Bool = true) async -> DiscoverResult? {
        if let pinged = await ping(ip) { return pinged }
        return useTCPFallback ? await tcpFallback(ip) : nil
    }

    /// ICMP ping via /sbin/ping. nil if host did not reply.
    static func ping(_ ip: String) async -> DiscoverResult? {
        await withCheckedContinuation { (continuation: CheckedContinuation<DiscoverResult?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                process.arguments = ["-c", "1", "-W", String(pingTimeoutMs), ip]
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0,
                      let output = String(data: data, encoding: .utf8),
                      let timeMatch = output.firstMatch(of: #/time=([0-9.]+)\s*ms/#),
                      let rtt = Double(timeMatch.1) else {
                    continuation.resume(returning: nil)
                    return
                }
                let ttl = output.firstMatch(of: #/ttl=([0-9]+)/#).flatMap { Int($0.1) }
                continuation.resume(returning: DiscoverResult(rttMs: rtt, ttl: ttl))
            }
        }
    }

    /// Concurrent TCP probe across fallback ports. Returns probe duration in ms if any port handshakes.
    static func tcpFallback(_ ip: String) async -> DiscoverResult? {
        let start = Date()
        let openPorts = await PortScanner.probe(ip, ports: tcpFallbackPorts, timeoutMs: tcpFallbackTimeoutMs)
        guard !openPorts.isEmpty else { return nil }
        let elapsedMs = max(0, Date().timeIntervalSince(start) * 1000)
        guard elapsedMs.isFinite else { return nil }
        return DiscoverResult(rttMs: elapsedMs, ttl: nil)
    }
}
