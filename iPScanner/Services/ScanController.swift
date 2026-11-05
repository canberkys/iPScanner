import Foundation
import Observation

@Observable
@MainActor
final class ScanController {
    enum State: Equatable {
        case idle
        case scanning(scanned: Int, total: Int)
        case done(scanned: Int, total: Int)
        case stopped(scanned: Int, total: Int)
    }

    static let portScanHostConcurrency = 32

    // Injectable operations keep lifecycle tests independent of the local network.
    struct Operations {
        var scan: @MainActor ([String], ScanProfile) -> AsyncStream<ScanEvent> = {
            NetworkScanner(profile: $1).scan(addresses: $0)
        }
        var probe: @Sendable (String, [Int]) async -> [Int] = {
            await PortScanner.probe($0, ports: $1)
        }
        var banner: @Sendable (String, [Int]) async -> String? = {
            await BannerProbe.fetch($0, openPorts: $1)
        }
    }
    private let operations: Operations
    private var generation = UUID()
    private(set) var phase = ScanPhase.discovery
    var canStart: Bool {
        !isScanning && (importedTargets != nil || !rangeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    struct ImportedTargets {
        let url: URL
        let targets: [String]
        let invalidLineCount: Int
    }

    var rangeInput: String = ""
    var searchQuery: String = ""
    var profile: ScanProfile = .standard
    private(set) var importedTargets: ImportedTargets?
    var rescanInterval: RescanInterval = .off {
        didSet { handleRescanIntervalChange() }
    }
    var selection: Set<Host.ID> = []
    var sortOrder: [KeyPathComparator<Host>] = [
        KeyPathComparator(\Host.ipNumeric, order: .forward)
    ]
    var labels: [String: String] = [:]   // anchor → label (anchor = MAC ?? IP)
    var savedRanges: [SavedRange] = []
    var showDeadHosts: Bool = false
    var filterHasOpenPorts: Bool = false
    var filterHasLabel: Bool = false
    var filterHasVendor: Bool = false
    var filterIdentifiedDevice: Bool = false

    var hasActiveScopeFilters: Bool {
        filterHasOpenPorts || filterHasLabel || filterHasVendor || filterIdentifiedDevice
    }

    var activeFilterNames: [String] {
        var names: [String] = []
        if filterHasOpenPorts { names.append("Open ports") }
        if filterHasLabel { names.append("Labeled") }
        if filterHasVendor { names.append("Vendor known") }
        if filterIdentifiedDevice { names.append("Identified type") }
        return names
    }

    // Dead probes are collected too; their presence does not mean a device was found.
    var hasResultConstraints: Bool { hasActiveScopeFilters || !searchQuery.isEmpty }
    var showsDiscoveryEmptyState: Bool {
        filteredHosts.isEmpty && !hasResultConstraints && aliveCount == 0
    }

    func clearScopeFilters() {
        filterHasOpenPorts = false
        filterHasLabel = false
        filterHasVendor = false
        filterIdentifiedDevice = false
    }

    private(set) var hosts: [Host] = []
    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastError: String?
    private(set) var portScanInProgress: Bool = false
    private(set) var portScanProgress: (scanned: Int, total: Int) = (0, 0)
    private(set) var warnings: [ScanWarning] = []
    private(set) var diff: SnapshotDiff?
    private var diffBaseline: ScanSnapshot?
    private var portScanTask: Task<Void, Never>?

    init(operations: Operations = Operations()) {
        self.operations = operations
        self.labels = PersistedStore.loadLabels()
        self.savedRanges = PersistedStore.loadRanges().sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    private var hostByIp: [String: Host] = [:]
    private var scanTask: Task<Void, Never>?
    private var startDate: Date?
    private var elapsedTimer: Timer?
    private var rescanTimer: Timer?
    private(set) var nextRescanAt: Date?

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    var aliveCount: Int { hosts.filter { $0.status == .alive }.count }

    var filteredHosts: [Host] {
        var visible = showDeadHosts ? hosts : hosts.filter { $0.status != .dead }
        if filterHasOpenPorts {
            visible = visible.filter { !$0.openPorts.isEmpty }
        }
        if filterHasLabel {
            visible = visible.filter { label(for: $0) != nil }
        }
        if filterHasVendor {
            visible = visible.filter { ($0.vendor?.isEmpty == false) }
        }
        if filterIdentifiedDevice {
            visible = visible.filter { DeviceClassifier.classify($0) != .unknown }
        }
        let rows: [Host]
        if searchQuery.isEmpty {
            rows = visible
        } else {
            let q = searchQuery.lowercased()
            rows = visible.filter { h in
                h.ip.lowercased().contains(q)
                    || (h.hostname?.lowercased().contains(q) ?? false)
                    || (h.mac?.lowercased().contains(q) ?? false)
                    || (h.vendor?.lowercased().contains(q) ?? false)
                    || (h.serviceTitle?.lowercased().contains(q) ?? false)
                    || (label(for: h)?.lowercased().contains(q) ?? false)
            }
        }
        return rows.sorted(using: sortOrder)
    }

    // MARK: - Labels

    func anchor(for host: Host) -> String {
        MACAddress.anchor(mac: host.mac, ip: host.ip)
    }

    func label(for host: Host) -> String? {
        MACAddress.label(in: labels, mac: host.mac, ip: host.ip)
    }

    func setLabel(_ value: String?, for host: Host) {
        let key = anchor(for: host)
        if let mac = host.mac, let address = MACAddress(mac) {
            for oldKey in labels.keys.filter({ MACAddress($0) == address }) { labels.removeValue(forKey: oldKey) }
        }
        // Retire an IP fallback after enrichment supplies the stable MAC anchor.
        labels.removeValue(forKey: host.ip)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            labels[key] = trimmed
        } else {
            labels.removeValue(forKey: key)
        }
        PersistedStore.saveLabels(labels)
    }

    // MARK: - Saved ranges

    var isCurrentRangeSaved: Bool {
        let key = rangeInput.trimmingCharacters(in: .whitespaces)
        return !key.isEmpty && savedRanges.contains { $0.range == key }
    }

    func toggleSaveCurrentRange() {
        let key = rangeInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        if let idx = savedRanges.firstIndex(where: { $0.range == key }) {
            savedRanges.remove(at: idx)
        } else {
            savedRanges.append(SavedRange(range: key, name: nil))
            sortSavedRanges()
        }
        PersistedStore.saveRanges(savedRanges)
    }

    func removeSavedRange(_ range: String) {
        savedRanges.removeAll { $0.range == range }
        PersistedStore.saveRanges(savedRanges)
    }

    func renameSavedRange(_ range: String, to name: String?) {
        guard let idx = savedRanges.firstIndex(where: { $0.range == range }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        savedRanges[idx].name = (trimmed?.isEmpty == false) ? trimmed : nil
        sortSavedRanges()
        PersistedStore.saveRanges(savedRanges)
    }

    func loadSavedRange(_ range: String) {
        guard !isScanning else { return }
        clearImportedFile()
        rangeInput = range
    }

    private func sortSavedRanges() {
        savedRanges.sort {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    func detectDefaultSubnetIfNeeded() {
        guard rangeInput.isEmpty, importedTargets == nil else { return }
        if let subnet = NetworkInterface.defaultSubnet() {
            rangeInput = subnet
        }
    }

    // MARK: - Imported targets (file)

    /// Result of attempting to load a target list file. Surfaced on the controller so the UI can render warnings.
    struct ImportSummary {
        let targetCount: Int
        let invalidLineCount: Int
    }

    @discardableResult
    func loadImportedFile(url: URL) throws -> ImportSummary {
        let result = try TargetFileParser.parse(url: url)
        if result.targets.isEmpty {
            throw TargetFileParser.ParseError.noTargets
        }
        importedTargets = ImportedTargets(
            url: url,
            targets: result.targets,
            invalidLineCount: result.invalidLines.count
        )
        lastError = nil
        return ImportSummary(
            targetCount: result.targets.count,
            invalidLineCount: result.invalidLines.count
        )
    }

    func clearImportedFile() {
        importedTargets = nil
    }

    func start() {
        guard !isScanning else { return }

        let addresses: [String]
        if let imported = importedTargets {
            addresses = imported.targets
        } else {
            let parsed = ScanRange.parseAll(rangeInput)
            if let badIdx = parsed.firstInvalidIndex {
                lastError = "Invalid range (chunk \(badIdx)). E.g. 10.0.0.0/24, 192.168.1.0/24, 172.16.5.50-172.16.5.100"
                return
            }
            guard !parsed.ranges.isEmpty else {
                lastError = "Enter an IP range (e.g. 10.0.0.0/24)."
                return
            }
            let totalHosts = ScanRange.totalHostCount(parsed.ranges)
            if totalHosts > 65_536 {
                lastError = "Total target list too large (\(totalHosts) hosts). Narrow the range or split the file."
                return
            }
            addresses = ScanRange.uniqueAddresses(parsed.ranges)
        }

        if addresses.count > 65_536 {
            lastError = "Total target list too large (\(addresses.count) hosts). Narrow the range or split the file."
            return
        }
        guard !addresses.isEmpty else {
            lastError = "No targets to scan."
            return
        }

        stop()
        generation = UUID()
        let runID = generation
        phase = .discovery
        selection = []
        lastError = nil
        hosts = []
        hostByIp = [:]
        warnings = []
        diff = nil
        cancelRescanTimer()
        startDate = Date()
        elapsed = 0
        state = .scanning(scanned: 0, total: addresses.count)

        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }

        let runProfile = profile
        let events = operations.scan(addresses, runProfile)
        scanTask = Task { [weak self] in
            for await event in events {
                guard let self, self.generation == runID, !Task.isCancelled else { return }
                self.handle(event: event)
            }
            guard let self, self.generation == runID, !Task.isCancelled else { return }
            if runProfile.autoPortScan {
                let targets = self.hosts.filter { $0.status == .alive }
                self.portScanInProgress = true
                self.portScanProgress = (0, targets.count)
                await self.executePortScan(targets: targets, ports: PortScanner.commonPorts,
                                           fetchBanners: true, runID: runID)
            }
            guard self.generation == runID, !Task.isCancelled else { return }
            self.finishRun()
        }
    }

    func stop() {
        generation = UUID() // Invalidate callbacks before cancelling their producers.
        scanTask?.cancel()
        scanTask = nil
        portScanTask?.cancel()
        portScanTask = nil
        portScanInProgress = false
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        cancelRescanTimer()
        if case .scanning(let s, let t) = state {
            state = .stopped(scanned: s, total: t)
        }
    }

    private func finishRun() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        portScanInProgress = false
        scanTask = nil
        portScanTask = nil
        if case .scanning(let s, let t) = state { state = .done(scanned: s, total: t) }
        recomputeDiff()
        scheduleRescan()
    }

    private func handleRescanIntervalChange() {
        cancelRescanTimer()
        // If the previous scan already finished and an interval is now set, prime the next tick.
        if case .done = state, rescanInterval.seconds != nil {
            scheduleRescan()
        }
    }

    private func scheduleRescan() {
        guard let interval = rescanInterval.seconds else { return }
        cancelRescanTimer()
        nextRescanAt = Date().addingTimeInterval(interval)
        let scheduledGeneration = generation
        rescanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == scheduledGeneration else { return }
                self.rescanTimer = nil
                self.nextRescanAt = nil
                if self.canStart {
                    self.start()
                }
            }
        }
    }

    private func cancelRescanTimer() {
        rescanTimer?.invalidate()
        rescanTimer = nil
        nextRescanAt = nil
    }

    func runPortScan(ports: [Int], fetchBanners: Bool = false, targetIds: Set<Host.ID>? = nil) {
        let ids = targetIds ?? selection
        let targets = hosts.filter { ids.contains($0.id) }
        guard !targets.isEmpty, !isScanning else { return }
        stop()
        generation = UUID()
        let runID = generation
        state = .scanning(scanned: hosts.count, total: hosts.count)
        portScanInProgress = true
        portScanProgress = (0, targets.count)
        portScanTask = Task { [weak self] in
            await self?.executePortScan(targets: targets, ports: ports,
                                        fetchBanners: fetchBanners, runID: runID)
            guard let self, self.generation == runID, !Task.isCancelled else { return }
            self.finishRun()
        }
    }

    func cancelPortScan() { stop() }

    private func executePortScan(targets: [Host], ports: [Int], fetchBanners: Bool, runID: UUID) async {
        guard generation == runID, !Task.isCancelled else { return }
        phase = .ports
        let probe = operations.probe
        let bannerProbe = operations.banner
        var completed = 0

        await withTaskGroup(of: (UUID, [Int]).self) { group in
            var iter = targets.makeIterator()
            for _ in 0..<min(Self.portScanHostConcurrency, targets.count) {
                guard let host = iter.next() else { break }
                let ip = host.ip
                let id = host.id
                group.addTask { (id, await probe(ip, ports)) }
            }
            while let (id, openPorts) = await group.next() {
                if Task.isCancelled || generation != runID { group.cancelAll(); break }
                if let idx = self.hosts.firstIndex(where: { $0.id == id }) {
                    self.hosts[idx].openPorts = openPorts
                    self.hostByIp[self.hosts[idx].ip] = self.hosts[idx]
                }
                completed += 1
                self.portScanProgress = (completed, targets.count)
                if let next = iter.next() {
                    let ip = next.ip
                    let nextId = next.id
                    group.addTask { (nextId, await probe(ip, ports)) }
                }
            }
        }

        if Task.isCancelled || generation != runID { return }
        guard fetchBanners else { return }
        phase = .banners

        // Use the hosts this port scan actually targeted, not the UI's live
        // `selection` — the deep-profile auto-scan targets alive hosts with no
        // regard for what (if anything) the user has selected, so filtering by
        // `selection` here silently drops every banner fetch when nothing is
        // selected.
        let targetIds = Set(targets.map(\.id))
        let bannerTargets: [(UUID, String, [Int])] = hosts
            .filter { targetIds.contains($0.id) }
            .compactMap { h in
                let banner = h.openPorts.filter { [80, 443, 22].contains($0) }
                return banner.isEmpty ? nil : (h.id, h.ip, banner)
            }

        portScanProgress = (0, bannerTargets.count)
        var failures = 0
        await withTaskGroup(of: (UUID, String?).self) { group in
            var pending = bannerTargets.makeIterator()
            for _ in 0..<min(Self.portScanHostConcurrency, bannerTargets.count) {
                guard let (id, ip, ports) = pending.next() else { break }
                group.addTask { (id, await bannerProbe(ip, ports)) }
            }
            for await (id, title) in group {
                if Task.isCancelled || generation != runID { group.cancelAll(); break }
                portScanProgress = (portScanProgress.scanned + 1, bannerTargets.count)
                if let (nextID, ip, ports) = pending.next() {
                    group.addTask { (nextID, await bannerProbe(ip, ports)) }
                }
                guard let title else { failures += 1; continue }
                if let idx = self.hosts.firstIndex(where: { $0.id == id }) {
                    self.hosts[idx].serviceTitle = title
                    self.hostByIp[self.hosts[idx].ip] = self.hosts[idx]
                }
            }
        }
        if generation == runID, !Task.isCancelled, failures > 0 {
            mergeWarning(.bannerFetchFailures(count: failures))
        }
    }

    // MARK: - Snapshot

    func makeSnapshot() -> ScanSnapshot {
        let records = hosts.map { h in
            ScanSnapshot.HostRecord(
                ip: h.ip,
                hostname: h.hostname,
                mac: h.mac,
                vendor: h.vendor,
                vendorStatus: h.vendorStatus,
                rttMs: h.rttMs,
                ttl: h.ttl,
                netbiosName: h.netbiosName,
                workgroup: h.workgroup,
                openPorts: h.openPorts,
                serviceTitle: h.serviceTitle,
                status: h.status
            )
        }
        var relevantLabels: [String: String] = [:]
        for h in hosts {
            let key = anchor(for: h)
            if let label = label(for: h) {
                relevantLabels[key] = label
            }
        }
        return ScanSnapshot(
            version: ScanSnapshot.currentVersion,
            createdAt: Date(),
            rangeInput: rangeInput,
            hosts: records,
            labels: relevantLabels
        )
    }

    func reportError(_ message: String?) {
        lastError = message
    }

    // MARK: - Comparison / diff

    func loadComparisonBaseline(_ snapshot: ScanSnapshot) {
        diffBaseline = snapshot
        recomputeDiff()
    }

    func clearComparison() {
        diffBaseline = nil
        diff = nil
    }

    func recomputeDiff() {
        guard let baseline = diffBaseline else { diff = nil; return }
        diff = SnapshotDiff.compute(current: hosts, baseline: baseline)
    }

    func change(for host: Host) -> HostChange? {
        diff?.changesByAnchor[anchor(for: host)]
    }

    func applySnapshot(_ snapshot: ScanSnapshot) {
        stop()
        scanTask = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        importedTargets = nil
        rangeInput = snapshot.rangeInput
        let restored = snapshot.hosts.map { rec in
            Host(
                ip: rec.ip,
                hostname: rec.hostname,
                mac: rec.mac,
                vendor: rec.vendor,
                vendorStatus: .historical,
                rttMs: rec.rttMs,
                ttl: rec.ttl,
                netbiosName: rec.netbiosName,
                workgroup: rec.workgroup,
                openPorts: rec.openPorts,
                serviceTitle: rec.serviceTitle,
                status: rec.status
            )
        }
        hosts = restored
        // A hand-edited or externally produced snapshot may repeat an IP; keep the
        // last record for that IP rather than crashing on the duplicate key.
        hostByIp = Dictionary(restored.map { ($0.ip, $0) }, uniquingKeysWith: { _, last in last })
        for (key, value) in snapshot.labels where labels[key] == nil {
            labels[key] = value
        }
        PersistedStore.saveLabels(labels)
        selection = []
        elapsed = 0
        startDate = nil
        warnings = []
        state = .done(scanned: restored.count, total: restored.count)
        lastError = nil
        recomputeDiff()
    }

    func deleteHosts(_ ids: Set<Host.ID>) {
        guard !ids.isEmpty else { return }
        let removedIPs = hosts.filter { ids.contains($0.id) }.map(\.ip)
        hosts.removeAll { ids.contains($0.id) }
        for ip in removedIPs { hostByIp.removeValue(forKey: ip) }
        selection.subtract(ids)
        recomputeDiff()
    }

    func refreshHost(_ id: Host.ID) async {
        guard let target = hosts.first(where: { $0.id == id }) else { return }
        let runID = generation
        let ip = target.ip
        if let idx = hosts.firstIndex(where: { $0.id == id }) {
            hosts[idx].status = .scanning
            hostByIp[ip] = hosts[idx]
        }

        let result = await NetworkScanner.discover(ip)
        guard generation == runID, !Task.isCancelled, let idx = hosts.firstIndex(where: { $0.id == id }) else { return }

        guard let result = result else {
            hosts[idx].status = .dead
            hosts[idx].rttMs = nil
            hosts[idx].ttl = nil
            hosts[idx].vendorStatus = .historical
            hostByIp[ip] = hosts[idx]
            recomputeDiff()
            return
        }

        try? await Task.sleep(for: .milliseconds(200))
        let arp = await ARPLookup.read()
        let arpTable = arp.entries
        async let hostnameTask = DNSResolver.reverseLookup(ip)
        async let netbiosTask: NetBIOSResolver.Result? =
            profile.includeNetBIOS ? NetBIOSResolver.resolve(ip) : nil
        async let mdnsTask: String? = MDNSReverseResolver.resolve(ip)
        let hostname = await hostnameTask
        let mdnsName = await mdnsTask
        let netbios = await netbiosTask
        let mac = arpTable[ip]
        let resolution = OUILookup.shared.resolve(mac)

        guard generation == runID, !Task.isCancelled, let idx2 = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[idx2].status = .alive
        hosts[idx2].rttMs = result.rttMs
        hosts[idx2].ttl = result.ttl
        hosts[idx2].hostname = hostname
        hosts[idx2].mac = mac
        hosts[idx2].vendor = resolution.vendor
        hosts[idx2].vendorStatus = mac == nil && arp.error != nil ? .queryFailed : resolution.status
        hosts[idx2].netbiosName = netbios?.computerName
        hosts[idx2].mdnsName = mdnsName
        hosts[idx2].workgroup = netbios?.workgroup
        hosts[idx2].openPorts = []
        hosts[idx2].serviceTitle = nil
        hostByIp[ip] = hosts[idx2]
        recomputeDiff()
    }

    func runWakeOnLAN(for ids: Set<Host.ID>) async {
        let macs = hosts
            .filter { ids.contains($0.id) }
            .compactMap { $0.mac }
        guard !macs.isEmpty else { return }
        await HostActions.wakeAll(macs: macs)
    }

    private func mergeWarning(_ w: ScanWarning) {
        switch w {
        case .arpFailed:
            if !warnings.contains(w) { warnings.append(w) }
        case .arpEmpty:
            if !warnings.contains(where: { if case .arpEmpty = $0 { return true } else { return false } }) {
                warnings.append(w)
            }
        case .bannerFetchFailures(let count):
            if let idx = warnings.firstIndex(where: {
                if case .bannerFetchFailures = $0 { return true } else { return false }
            }), case .bannerFetchFailures(let existing) = warnings[idx] {
                warnings[idx] = .bannerFetchFailures(count: existing + count)
            } else {
                warnings.append(.bannerFetchFailures(count: count))
            }
        }
    }

    private func handle(event: ScanEvent) {
        switch event {
        case .phase(let next):
            phase = next
        case .progress(let scanned, let total):
            state = .scanning(scanned: scanned, total: total)
        case .warning(let w):
            mergeWarning(w)
        case .host(let h):
            if let existing = hostByIp[h.ip] {
                let merged = existing.merged(with: h)
                hostByIp[h.ip] = merged
                if let idx = hosts.firstIndex(where: { $0.ip == h.ip }) {
                    hosts[idx] = merged
                }
            } else {
                hostByIp[h.ip] = h
                hosts.append(h)
            }
        case .done:
            break // The owner completes only after optional port/banner enrichment.
        }
    }
}
