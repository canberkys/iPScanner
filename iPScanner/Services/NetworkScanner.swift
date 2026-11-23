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

/// Outcome of one ping process. `launchFailed` is kept apart from `noReply` so a
/// missing or blocked /sbin/ping is reported instead of marking every host dead.
enum PingResult: Sendable {
    case reply(DiscoverResult)
    case noReply
    case launchFailed(String)
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
        continuation.yield(.progress(scanned: 0, total: total))

        // --- Phase 1: discover (ping → TCP fallback) with bounded concurrency ---
        // Always yield dead hosts so the UI can filter on demand without re-scanning.
        var alive: [(ip: String, rtt: Double, ttl: Int?)] = []
        var scanned = 0
        var pingLaunchError: String?

        await withTaskGroup(of: (String, Discovery).self) { group in
            var iter = addresses.makeIterator()
            for _ in 0..<min(pingConcurrency, addresses.count) {
                guard let ip = iter.next() else { break }
                group.addTask { (ip, await Self.discoverDetailed(ip, useTCPFallback: useTCPFallback)) }
            }

            while let (ip, discovery) = await group.next() {
                let result = discovery.result
                if pingLaunchError == nil, let error = discovery.pingLaunchError { pingLaunchError = error }
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
                    group.addTask { (next, await Self.discoverDetailed(next, useTCPFallback: useTCPFallback)) }
                }
            }
            if Task.isCancelled { group.cancelAll() }
        }

        if let pingLaunchError {
            continuation.yield(.warning(.pingUnavailable(pingLaunchError)))
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

        // --- Phase 2: enrich (DNS + MAC + Vendor) per alive host ---
        await withTaskGroup(of: Host.self) { group in
            var iter = alive.makeIterator()

            func enqueue(_ entry: (ip: String, rtt: Double, ttl: Int?)) {
                let mac = arpTable[entry.ip]
                let resolution = oui.resolve(mac)
                group.addTask {
                    async let hostname = DNSResolver.reverseLookup(entry.ip)
                    async let netbios: NetBIOSResolver.Result? =
                        includeNetBIOS ? NetBIOSResolver.resolve(entry.ip) : nil
                    let resolvedHost = await hostname
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

    struct Discovery: Sendable {
        var result: DiscoverResult?
        var pingLaunchError: String?
    }

    /// Returns RTT and (when ICMP succeeded) TTL if the host responded.
    static func discover(_ ip: String, useTCPFallback: Bool = true) async -> DiscoverResult? {
        await discoverDetailed(ip, useTCPFallback: useTCPFallback).result
    }

    static func discoverDetailed(_ ip: String, useTCPFallback: Bool = true) async -> Discovery {
        guard !Task.isCancelled else { return Discovery() }
        var launchError: String?
        switch await ping(ip) {
        case .reply(let pinged): return Discovery(result: pinged)
        case .noReply: break
        case .launchFailed(let message): launchError = message
        }
        guard !Task.isCancelled else { return Discovery(pingLaunchError: launchError) }
        let fallback = useTCPFallback ? await tcpFallback(ip) : nil
        return Discovery(result: fallback, pingLaunchError: launchError)
    }

    /// ICMP ping via /sbin/ping.
    static func ping(_ ip: String) async -> PingResult {
        await runPingDetailed(executable: URL(fileURLWithPath: "/sbin/ping"),
                              arguments: ["-n", "-c", "1", "-W", String(pingTimeoutMs), "-t", "1", ip],
                              timeout: Double(pingTimeoutMs) / 1000 + 0.1)
    }

    /// nil if the host did not reply or ping could not run.
    static func runPing(executable: URL, arguments: [String], timeout: Double) async -> DiscoverResult? {
        if case .reply(let result) = await runPingDetailed(executable: executable, arguments: arguments, timeout: timeout) {
            return result
        }
        return nil
    }

    /// Bounds the entire process, including route resolution; -W alone only limits reply waiting.
    static func runPingDetailed(executable: URL, arguments: [String], timeout: Double) async -> PingResult {
        let runner = PingProcess()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<PingResult, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments
                    let stdout = Pipe()
                    process.standardOutput = stdout
                    process.standardError = FileHandle.nullDevice

                    do {
                        guard try runner.start(process) else {
                            continuation.resume(returning: .noReply) // cancelled before launch
                            return
                        }
                    } catch {
                        continuation.resume(returning: .launchFailed("\(executable.path) could not run: \(error.localizedDescription)"))
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
                        continuation.resume(returning: .noReply)
                        return
                    }
                    let ttl = output.firstMatch(of: #/ttl=([0-9]+)/#).flatMap { Int($0.1) }
                    continuation.resume(returning: .reply(DiscoverResult(rttMs: rtt, ttl: ttl)))
                }
            }
        } onCancel: { runner.cancel() }
    }

    /// Concurrent TCP probe across fallback ports. The host counts as up as soon as any
    /// port completes a handshake or answers with a reset (connection refused), and the
    /// RTT is the time to that first answer rather than to the slowest port.
    static func tcpFallback(_ ip: String, ports: [Int] = tcpFallbackPorts, timeoutMs: Int = tcpFallbackTimeoutMs) async -> DiscoverResult? {
        guard !Task.isCancelled, !ports.isEmpty else { return nil }
        let clock = ContinuousClock()
        let start = clock.now
        return await withTaskGroup(of: PortScanner.ProbeOutcome.self) { group in
            for port in ports {
                group.addTask { await PortScanner.outcome(ip: ip, port: port, timeoutMs: timeoutMs) }
            }
            while let outcome = await group.next() {
                guard outcome != .noResponse else { continue }
                let elapsed = start.duration(to: clock.now)
                group.cancelAll()
                let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
                return DiscoverResult(rttMs: max(0, ms), ttl: nil)
            }
            return nil
        }
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
