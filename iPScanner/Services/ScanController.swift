import Foundation
import Observation

@Observable
@MainActor
final class ScanController {
    enum State: Equatable {
        case idle
        case scanning(scanned: Int, total: Int)
        case done(scanned: Int, total: Int)
    }

    static let portScanHostConcurrency = 4

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

    init() {
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
        host.mac ?? host.ip
    }

    func label(for host: Host) -> String? {
        labels[anchor(for: host)]
    }

    func setLabel(_ value: String?, for host: Host) {
        let key = anchor(for: host)
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

        lastError = nil
        hosts = []
        hostByIp = [:]
        warnings = []
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

        let scanner = NetworkScanner(profile: profile)
        let runProfile = profile
        scanTask = Task { [weak self] in
            for await event in scanner.scan(addresses: addresses) {
                guard let self else { return }
                self.handle(event: event)
                if Task.isCancelled { break }
            }
            // Deep profile: chain a common-port scan with banner fetch on alive hosts.
            if !Task.isCancelled, runProfile.autoPortScan {
                guard let self else { return }
                await MainActor.run {
                    let aliveIDs = Set(self.hosts.filter { $0.status == .alive }.map { $0.id })
                    guard !aliveIDs.isEmpty,
                          let ports = PortScanner.parsePorts(PortScanner.defaultPortsInput) else { return }
                    self.runPortScan(ports: ports, fetchBanners: true, targetIds: aliveIDs)
                }
            }
        }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        cancelRescanTimer()
        if case .scanning(let s, let t) = state {
            state = .done(scanned: s, total: t)
        }
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
        rescanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.rescanTimer = nil
                self.nextRescanAt = nil
                if !self.isScanning, !self.rangeInput.trimmingCharacters(in: .whitespaces).isEmpty {
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
        guard !targets.isEmpty, !portScanInProgress else { return }
        portScanInProgress = true
        portScanProgress = (0, targets.count)

        portScanTask = Task { [weak self] in
            await self?.executePortScan(targets: targets, ports: ports, fetchBanners: fetchBanners)
            await MainActor.run { [weak self] in
                self?.portScanInProgress = false
                self?.portScanTask = nil
            }
        }
    }

    func cancelPortScan() {
        portScanTask?.cancel()
        portScanTask = nil
        portScanInProgress = false
    }

    private func executePortScan(targets: [Host], ports: [Int], fetchBanners: Bool) async {
        var completed = 0

        await withTaskGroup(of: (UUID, [Int]).self) { group in
            var iter = targets.makeIterator()
            for _ in 0..<min(Self.portScanHostConcurrency, targets.count) {
                guard let host = iter.next() else { break }
                let ip = host.ip
                let id = host.id
                group.addTask { (id, await PortScanner.probe(ip, ports: ports)) }
            }
            while let (id, openPorts) = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                if let idx = self.hosts.firstIndex(where: { $0.id == id }) {
                    self.hosts[idx].openPorts = openPorts
                    self.hostByIp[self.hosts[idx].ip] = self.hosts[idx]
                }
                completed += 1
                self.portScanProgress = (completed, targets.count)
                if let next = iter.next() {
                    let ip = next.ip
                    let nextId = next.id
                    group.addTask { (nextId, await PortScanner.probe(ip, ports: ports)) }
                }
            }
        }

        if Task.isCancelled { return }
        guard fetchBanners else { return }

        let bannerTargets: [(UUID, String, [Int])] = hosts
            .filter { selection.contains($0.id) }
            .compactMap { h in
                let banner = h.openPorts.filter { [80, 443, 22].contains($0) }
                return banner.isEmpty ? nil : (h.id, h.ip, banner)
            }

        var failures = 0
        await withTaskGroup(of: (UUID, String?).self) { group in
            for (id, ip, ports) in bannerTargets {
                group.addTask { (id, await BannerProbe.fetch(ip, openPorts: ports)) }
            }
            for await (id, title) in group {
                if Task.isCancelled { group.cancelAll(); break }
                guard let title else { failures += 1; continue }
                if let idx = self.hosts.firstIndex(where: { $0.id == id }) {
                    self.hosts[idx].serviceTitle = title
                    self.hostByIp[self.hosts[idx].ip] = self.hosts[idx]
                }
            }
        }
        if failures > 0 {
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
                rttMs: h.rttMs,
                openPorts: h.openPorts,
                serviceTitle: h.serviceTitle
            )
        }
        var relevantLabels: [String: String] = [:]
        for h in hosts {
            let key = anchor(for: h)
            if let label = labels[key] {
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
        diff?.changesByAnchor[host.mac ?? host.ip]
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
                rttMs: rec.rttMs,
                openPorts: rec.openPorts,
                serviceTitle: rec.serviceTitle,
                status: .alive
            )
        }
        hosts = restored
        hostByIp = Dictionary(uniqueKeysWithValues: restored.map { ($0.ip, $0) })
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
    }

    func deleteHosts(_ ids: Set<Host.ID>) {
        guard !ids.isEmpty else { return }
        let removedIPs = hosts.filter { ids.contains($0.id) }.map(\.ip)
        hosts.removeAll { ids.contains($0.id) }
        for ip in removedIPs { hostByIp.removeValue(forKey: ip) }
        selection.subtract(ids)
    }

    func refreshHost(_ id: Host.ID) async {
        guard let target = hosts.first(where: { $0.id == id }) else { return }
        let ip = target.ip
        if let idx = hosts.firstIndex(where: { $0.id == id }) {
            hosts[idx].status = .scanning
            hostByIp[ip] = hosts[idx]
        }

        let rtt = await NetworkScanner.discover(ip)
        guard let idx = hosts.firstIndex(where: { $0.id == id }) else { return }

        if rtt == nil {
            hosts[idx].status = .dead
            hosts[idx].rttMs = nil
            hostByIp[ip] = hosts[idx]
            return
        }

        try? await Task.sleep(for: .milliseconds(200))
        let arpTable = await ARPLookup.table()
        let hostname = await DNSResolver.reverseLookup(ip)
        let mac = arpTable[ip]
        let vendor = mac.flatMap { OUILookup.shared.vendor(forMAC: $0) }

        guard let idx2 = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[idx2].status = .alive
        hosts[idx2].rttMs = rtt
        if let h = hostname { hosts[idx2].hostname = h }
        if let m = mac { hosts[idx2].mac = m }
        if let v = vendor { hosts[idx2].vendor = v }
        hostByIp[ip] = hosts[idx2]
    }

    func runWakeOnLAN(for ids: Set<Host.ID>) async {
        let macs = hosts
            .filter { ids.contains($0.id) }
            .compactMap { $0.mac }
        guard !macs.isEmpty else { return }
        await WakeOnLAN.wakeAll(macs: macs)
    }

    private func mergeWarning(_ w: ScanWarning) {
        switch w {
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
        case .progress(let scanned, let total):
            state = .scanning(scanned: scanned, total: total)
        case .warning(let w):
            mergeWarning(w)
        case .host(let h):
            if let existing = hostByIp[h.ip] {
                var merged = existing
                if let v = h.hostname { merged.hostname = v }
                if let v = h.mac { merged.mac = v }
                if let v = h.vendor { merged.vendor = v }
                if let v = h.rttMs { merged.rttMs = v }
                if let v = h.serviceTitle { merged.serviceTitle = v }
                merged.openPorts = h.openPorts.isEmpty ? merged.openPorts : h.openPorts
                merged.status = h.status
                hostByIp[h.ip] = merged
                if let idx = hosts.firstIndex(where: { $0.ip == h.ip }) {
                    hosts[idx] = merged
                }
            } else {
                hostByIp[h.ip] = h
                hosts.append(h)
            }
        case .done:
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            if case .scanning(let s, let t) = state {
                state = .done(scanned: s, total: t)
            } else {
                state = .done(scanned: hosts.count, total: hosts.count)
            }
            recomputeDiff()
            scheduleRescan()
        }
    }
}
