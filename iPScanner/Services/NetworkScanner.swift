import Foundation
import Darwin

protocol NetworkScanning: Sendable {
    func scan(_ range: ScanRange) -> AsyncStream<ScanEvent>
}

struct DiscoverResult: Sendable, Hashable {
    let rttMs: Double
    /// Only populated for ICMP responses. TCP fallback probes don't expose a useful TTL.
    let ttl: Int?
}

struct NetworkScanner: NetworkScanning {
    static let pingConcurrency = 96
    static let enrichConcurrency = 32
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
        let includeNetBIOS = profile.includeNetBIOS
        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await Self.run(
                    addresses: addresses,
                    useTCPFallback: useTCPFallback,
                    includeNetBIOS: includeNetBIOS,
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
        includeNetBIOS: Bool = false,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        let total = addresses.count
        async let ipv6Neighbors = IPv6Neighbors.discover(interfaces: NetworkInterface.scannableInterfaces().map(\.name))
        continuation.yield(.progress(scanned: 0, total: total))

        // --- Phase 1: discover (ping → TCP fallback) with bounded concurrency ---
        // Always yield dead hosts so the UI can filter on demand without re-scanning.
        var alive: [(ip: String, rtt: Double?, ttl: Int?)] = []
        var scanned = 0

        // One ICMP socket pings every address at once; only silent addresses need the
        // slower TCP/mDNS probes below. Falls back to per-address pings if no socket.
        var swept = await ICMPSweeper.sweep(addresses)
        var arpConfirmed: [String: String] = [:]
        if swept != nil {
            // Second pass for silent addresses: sleepy devices that missed the first ARP
            // request get another chance. Both passes make macOS resolve each address via ARP.
            let silent = addresses.filter { swept?[$0] == nil }
            if let again = await ICMPSweeper.sweep(silent, waitMs: 500) {
                swept = swept?.merging(again) { first, _ in first }
            }
            try? await Task.sleep(for: .milliseconds(200))
            let arp = await ARPLookup.read()
            if arp.error == nil {
                // Devices that drop ping still answer ARP, so a MAC entry means the host is up.
                for ip in addresses where swept?[ip] == nil {
                    if let mac = arp.entries[ip], !mac.isEmpty { arpConfirmed[ip] = mac }
                }
            } else {
                swept = nil  // ARP unavailable: use the slower per-address probes instead
            }
        }
        for ip in addresses {
            if let reply = swept?[ip] {
                scanned += 1
                alive.append((ip, reply.rttMs, reply.ttl))
                continuation.yield(.host(Host(ip: ip, rttMs: reply.rttMs, ttl: reply.ttl, status: .alive)))
            } else if let mac = arpConfirmed[ip] {
                scanned += 1
                alive.append((ip, nil, nil))
                continuation.yield(.host(Host(ip: ip, mac: mac, status: .alive)))
            }
        }
        continuation.yield(.progress(scanned: scanned, total: total))
        let skipPing = swept != nil
        let pending: [String]
        if swept != nil {
            // Everything not found by ICMP or ARP is not on the network.
            pending = []
            for ip in addresses where swept?[ip] == nil && arpConfirmed[ip] == nil {
                scanned += 1
                continuation.yield(.host(Host(ip: ip, status: .dead)))
            }
            continuation.yield(.progress(scanned: scanned, total: total))
        } else {
            pending = addresses
        }

        await withTaskGroup(of: (String, DiscoverResult?).self) { group in
            var iter = pending.makeIterator()
            for _ in 0..<min(pingConcurrency, pending.count) {
                guard let ip = iter.next() else { break }
                group.addTask { (ip, await Self.discover(ip, useTCPFallback: useTCPFallback, skipPing: skipPing)) }
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
                    group.addTask { (next, await Self.discover(next, useTCPFallback: useTCPFallback, skipPing: skipPing)) }
                }
            }
            if Task.isCancelled { group.cancelAll() }
        }

        if Task.isCancelled {
            continuation.yield(.done)
            continuation.finish()
            return
        }

        continuation.yield(.phase(.enrichment))
        // --- ARP grace ---
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { continuation.finish(); return }
        let arp = await ARPLookup.read()
        let arpTable = arp.entries
        if let error = arp.error { continuation.yield(.warning(.arpFailed(error))) }
        if arp.error == nil, arpTable.isEmpty, !alive.isEmpty {
            continuation.yield(.warning(.arpEmpty))
        }
        let oui = OUILookup.shared
        let v6ByMAC = await ipv6Neighbors

        // --- ARP-confirmed hosts: devices that drop ping and TCP probes (phones, tablets, IoT)
        // still answer ARP, so any scanned address with a MAC entry is on the network.
        let known = Set(alive.map(\.ip))
        for ip in addresses where !known.contains(ip) {
            guard let mac = arpTable[ip], !mac.isEmpty else { continue }
            alive.append((ip, nil, nil))
            continuation.yield(.host(Host(ip: ip, mac: mac, status: .alive)))
        }

        // --- Phase 2: enrich (DNS + MAC + Vendor) per alive host ---
        await withTaskGroup(of: Host.self) { group in
            var iter = alive.makeIterator()

            func enqueue(_ entry: (ip: String, rtt: Double?, ttl: Int?)) {
                let mac = arpTable[entry.ip]
                let resolution = oui.resolve(mac)
                group.addTask {
                    async let hostname = DNSResolver.reverseLookup(entry.ip)
                    async let netbios: NetBIOSResolver.Result? =
                        includeNetBIOS ? NetBIOSResolver.resolve(entry.ip) : nil
                    async let mdnsLookup: String? = MDNSReverseResolver.resolveWithRetry(entry.ip)
                    let resolvedHost = await hostname
                    let mdnsName = await mdnsLookup
                    let nb = await netbios
                    return Host(
                        ip: entry.ip,
                        hostname: resolvedHost,
                        mac: mac,
                        vendor: resolution.vendor,
                        vendorStatus: mac == nil && arp.error != nil ? .queryFailed : resolution.status,
                        rttMs: entry.rtt,
                        ttl: entry.ttl,
                        netbiosName: nb?.computerName,
                        mdnsName: mdnsName,
                        ipv6Addresses: mac.flatMap { v6ByMAC[$0] } ?? [],
                        workgroup: nb?.workgroup,
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
    static func discover(_ ip: String, useTCPFallback: Bool = true, skipPing: Bool = false) async -> DiscoverResult? {
        guard !Task.isCancelled else { return nil }
        // Ask for the mDNS name at the same time as ping/TCP, so devices that ignore
        // both (phones, tablets, some IoT) are still found at no extra wall time.
        let started = Date()
        async let mdnsReply: String? = MDNSReverseResolver.resolve(ip)
        var found: DiscoverResult?
        if !skipPing { found = await ping(ip) }
        if found == nil, !Task.isCancelled, useTCPFallback {
            found = await tcpFallback(ip)
        }
        let announced = await mdnsReply
        if let found { return found }
        guard announced != nil else { return nil }
        return DiscoverResult(rttMs: max(0, Date().timeIntervalSince(started) * 1000), ttl: nil)
    }

    /// ICMP ping via /sbin/ping. nil if host did not reply.
    static func ping(_ ip: String) async -> DiscoverResult? {
        await runPing(executable: URL(fileURLWithPath: "/sbin/ping"),
                      arguments: ["-n", "-c", "1", "-W", String(pingTimeoutMs), "-t", "1", ip],
                      timeout: Double(pingTimeoutMs) / 1000 + 0.1)
    }

    /// Bounds the entire process, including route resolution; -W alone only limits reply waiting.
    static func runPing(executable: URL, arguments: [String], timeout: Double) async -> DiscoverResult? {
        let runner = PingProcess()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<DiscoverResult?, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments
                    let stdout = Pipe()
                    process.standardOutput = stdout
                    process.standardError = FileHandle.nullDevice

                    do {
                        guard try runner.start(process) else {
                            continuation.resume(returning: nil)
                            return
                        }
                    } catch {
                        continuation.resume(returning: nil)
                        return
                    }

                    let deadline = DispatchWorkItem { runner.cancel() }
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: deadline)
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    deadline.cancel()
                    runner.finish()

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
        } onCancel: { runner.cancel() }
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

/// Serializes process launch against cancellation, including cancellation before launch.
private final class PingProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func start(_ process: Process) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        self.process = process
        try process.run()
        return true
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        process = nil
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}
