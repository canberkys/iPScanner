import XCTest
@testable import iPScanner

/// Regression tests for the 1.3.2 fixes (roadmap phase 0).
final class PatchRegressionTests: XCTestCase {

    // MARK: - Snapshot labels are not persisted silently

    @MainActor func testOpeningSnapshotShowsLabelsWithoutSavingThem() {
        let previous = PersistedStore.loadLabels()
        defer { PersistedStore.saveLabels(previous) }
        PersistedStore.saveLabels(["AA:BB:CC:00:00:01": "Mine"])

        let controller = ScanController()
        defer { controller.stop() }
        let snapshot = ScanSnapshot(
            version: ScanSnapshot.currentVersion, createdAt: Date(), rangeInput: "10.0.0.0/30",
            hosts: [
                .init(ip: "10.0.0.1", hostname: nil, mac: "AA:BB:CC:00:00:01", vendor: nil, vendorStatus: nil,
                      rttMs: nil, ttl: nil, netbiosName: nil, workgroup: nil, openPorts: [], serviceTitle: nil, status: .alive),
                .init(ip: "10.0.0.2", hostname: nil, mac: "AA:BB:CC:00:00:02", vendor: nil, vendorStatus: nil,
                      rttMs: nil, ttl: nil, netbiosName: nil, workgroup: nil, openPorts: [], serviceTitle: nil, status: .alive)
            ],
            labels: ["AA:BB:CC:00:00:01": "Theirs", "AA:BB:CC:00:00:02": "Printer"]
        )
        controller.applySnapshot(snapshot)

        XCTAssertEqual(controller.label(for: controller.hosts[0]), "Mine", "Local labels win")
        XCTAssertEqual(controller.label(for: controller.hosts[1]), "Printer", "File labels are shown")
        XCTAssertNil(PersistedStore.loadLabels()["AA:BB:CC:00:00:02"], "…but not saved")
        XCTAssertEqual(controller.importableSnapshotLabelCount, 1)

        controller.importSnapshotLabels()
        XCTAssertEqual(PersistedStore.loadLabels()["AA:BB:CC:00:00:02"], "Printer")
        XCTAssertEqual(PersistedStore.loadLabels()["AA:BB:CC:00:00:01"], "Mine", "Existing labels unchanged")
    }

    @MainActor func testClearingALabelShownFromSnapshotRemovesIt() {
        let previous = PersistedStore.loadLabels()
        defer { PersistedStore.saveLabels(previous) }
        PersistedStore.saveLabels([:])
        let controller = ScanController()
        defer { controller.stop() }
        controller.applySnapshot(ScanSnapshot(
            version: 1, createdAt: Date(), rangeInput: "10.0.0.5",
            hosts: [.init(ip: "10.0.0.5", hostname: nil, mac: nil, vendor: nil, vendorStatus: nil, rttMs: nil, ttl: nil,
                          netbiosName: nil, workgroup: nil, openPorts: [], serviceTitle: nil, status: .alive)],
            labels: ["10.0.0.5": "Old"]))
        controller.setLabel(nil, for: controller.hosts[0])
        XCTAssertNil(controller.label(for: controller.hosts[0]))
    }

    // MARK: - Port scans merge

    func testPortScanKeepsPortsOutsideTheScannedSet() {
        // Earlier scan found 22 and 80; a Web scan (80, 443, 8080) now finds only 443.
        XCTAssertEqual(ScanController.mergePortScan(previous: [22, 80], scanned: [80, 443, 8080], open: [443]), [22, 443])
        XCTAssertEqual(ScanController.mergePortScan(previous: [], scanned: [22], open: [22]), [22])
        XCTAssertEqual(ScanController.mergePortScan(previous: [22], scanned: [22], open: []), [])
    }

    // MARK: - Snapshot range for imported targets

    func testCollapsedRangeInputRoundTrips() {
        let ips = ["10.0.0.3", "10.0.0.1", "10.0.0.2", "10.0.0.9", "10.0.1.0", "10.0.0.255", "10.0.0.2"]
        let collapsed = IPv4.collapsedRangeInput(ips)
        XCTAssertEqual(collapsed, "10.0.0.1-10.0.0.3, 10.0.0.9, 10.0.0.255-10.0.1.0")
        let parsed = ScanRange.parseAll(collapsed)
        XCTAssertNil(parsed.firstInvalidIndex)
        XCTAssertEqual(ScanRange.uniqueAddresses(parsed.ranges), Array(Set(ips)).sorted { IPv4.uint32(from: $0)! < IPv4.uint32(from: $1)! })
        XCTAssertEqual(IPv4.collapsedRangeInput([]), "")
    }

    @MainActor func testSnapshotOfImportedListRecordsTargets() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "10.0.0.7\n10.0.0.8\n10.0.0.20\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = ScanController()
        defer { controller.stop() }
        controller.rangeInput = ""
        try controller.loadImportedFile(url: url)
        XCTAssertEqual(controller.makeSnapshot().rangeInput, "10.0.0.7-10.0.0.8, 10.0.0.20")
    }

    // MARK: - Snapshot format version

    func testNewerSnapshotFormatIsRejectedClearly() {
        let json = #"{"version": 99, "createdAt": "2026-01-01T00:00:00Z", "rangeInput": "", "hosts": [], "labels": {}}"#
        XCTAssertThrowsError(try SnapshotIO.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? SnapshotIO.SnapshotError, .unsupportedVersion(99))
        }
    }

    // MARK: - Persisted data is not destroyed

    func testUnreadablePreferencesAreBackedUpAndPartiallyRecovered() throws {
        let suite = "iPScannerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let original = PersistedStore.defaults
        PersistedStore.defaults = defaults
        defer {
            PersistedStore.defaults = original
            defaults.removePersistentDomain(forName: suite)
        }

        defaults.set(["10.0.0.1": "Router", "10.0.0.2": 42], forKey: "iPScanner.labels")
        XCTAssertEqual(PersistedStore.loadLabels(), ["10.0.0.1": "Router"])
        XCTAssertNotNil(PersistedStore.consumeRecoveryNotice())

        defaults.set(Data("not json".utf8), forKey: "iPScanner.savedRangesV2")
        XCTAssertEqual(PersistedStore.loadRanges(), [])
        XCTAssertNotNil(PersistedStore.consumeRecoveryNotice())

        let backups = defaults.dictionaryRepresentation().keys.filter { $0.contains(".backup-") }
        XCTAssertEqual(Set(backups.map { $0.components(separatedBy: ".backup-")[0] }),
                       ["iPScanner.labels", "iPScanner.savedRangesV2"])
    }

    // MARK: - Wake-on-LAN destinations

    func testWakeOnLANTargetsLocalSubnetsButNotTunnels() {
        let interfaces = [
            NetworkInterfaceInfo(name: "en0", ipv4: "192.168.1.20", netmaskBits: 24),
            NetworkInterfaceInfo(name: "en7", ipv4: "10.20.0.5", netmaskBits: 16),
            NetworkInterfaceInfo(name: "utun3", ipv4: "100.64.0.2", netmaskBits: 24),
            NetworkInterfaceInfo(name: "en9", ipv4: "172.16.0.1", netmaskBits: 32)
        ]
        XCTAssertEqual(WakeOnLAN.broadcastDestinations(interfaces: interfaces),
                       ["255.255.255.255", "192.168.1.255", "10.20.255.255"])
    }

    func testWakeOnLANRejectsInvalidInput() {
        XCTAssertThrowsError(try WakeOnLAN.wake(mac: "zz", destinations: ["127.0.0.1"]))
        XCTAssertThrowsError(try WakeOnLAN.send(Data([1]), to: "010.0.0.1", port: 9))
    }

    func testWakeOnLANSendsOverLoopback() throws {
        // A real send with SO_BROADCAST set; loopback avoids touching the user's network.
        XCTAssertNoThrow(try WakeOnLAN.wake(mac: "28:6f:b9:00:00:01", destinations: ["127.0.0.1"], port: 9))
    }
}
