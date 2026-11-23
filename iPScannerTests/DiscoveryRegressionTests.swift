import XCTest
import Darwin
@testable import iPScanner

final class DiscoveryRegressionTests: XCTestCase {
    func testPingProcessDeadlineStopsAnUnresponsiveProcess() async {
        let start = Date()
        let result = await NetworkScanner.runPing(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.1)
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testPingProcessCancellationBeforeAndAfterLaunch() async {
        for delay in [0, 100] {
            let task = Task {
                await NetworkScanner.runPing(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 5)
            }
            if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
            let start = Date()
            task.cancel()
            let result = await task.value
            XCTAssertNil(result)
            XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        }
    }

    func testPingStillDiscoversLocalhost() async {
        guard case .reply(let result) = await NetworkScanner.ping("127.0.0.1") else {
            return XCTFail("Expected an ICMP reply from localhost")
        }
        XCTAssertNotNil(result.ttl)
    }

    func testPingLaunchFailureIsReportedSeparately() async {
        let result = await NetworkScanner.runPingDetailed(
            executable: URL(fileURLWithPath: "/nonexistent/ping"), arguments: ["127.0.0.1"], timeout: 1)
        guard case .launchFailed(let message) = result else { return XCTFail("Expected launchFailed, got \(result)") }
        XCTAssertTrue(message.contains("/nonexistent/ping"))
    }

    func testTCPFallbackTreatsConnectionRefusedAsAlive() async throws {
        // Bind and immediately close a loopback port so connecting to it gets a TCP reset.
        let port = try closedLoopbackPort()
        let result = await NetworkScanner.tcpFallback("127.0.0.1", ports: [port], timeoutMs: 2000)
        XCTAssertNotNil(result, "A reset proves the host is up")
        XCTAssertLessThan(result?.rttMs ?? .infinity, 1000, "RTT should be the first answer, not the timeout")
    }

    func testProbeDistinguishesRefusedFromOpen() async throws {
        let port = try closedLoopbackPort()
        let outcome = await PortScanner.outcome(ip: "127.0.0.1", port: port, timeoutMs: 2000)
        XCTAssertEqual(outcome, .refused)
        let open = await PortScanner.probe("127.0.0.1", ports: [port], timeoutMs: 500)
        XCTAssertEqual(open, [], "Refused ports are not open ports")
    }

    private func closedLoopbackPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EBADF) }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr -> Bool in
                Darwin.bind(fd, ptr, len) == 0 && Darwin.getsockname(fd, ptr, &len) == 0
            }
        }
        guard bound else { throw POSIXError(.EADDRINUSE) }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    @MainActor
    private func scannedController(_ hosts: [iPScanner.Host]) async -> ScanController {
        var operations = ScanController.Operations()
        operations.scan = { _, _ in AsyncStream { stream in
            for host in hosts { stream.yield(.host(host)) }
            stream.yield(.done)
            stream.finish()
        } }
        let controller = ScanController(operations: operations)
        controller.rangeInput = "127.0.0.1"
        controller.profile = .quick
        controller.start()
        for _ in 0..<200 where controller.isScanning { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(controller.isScanning)
        return controller
    }

    @MainActor func testDeadProbesDoNotClaimDevicesWereHiddenByFilters() async {
        let controller = await scannedController([Host(ip: "127.0.0.1", status: .dead)])
        defer { controller.stop() }
        XCTAssertTrue(controller.showsDiscoveryEmptyState)
        controller.showDeadHosts = true
        XCTAssertFalse(controller.showsDiscoveryEmptyState)
        XCTAssertEqual(controller.filteredHosts.count, 1)
    }

    @MainActor func testClearFiltersRestoresAliveRowsWithoutShowingDeadProbes() async {
        let controller = await scannedController([Host(ip: "127.0.0.1", status: .alive), Host(ip: "127.0.0.2", status: .dead)])
        defer { controller.stop() }
        controller.filterHasVendor = true
        XCTAssertTrue(controller.filteredHosts.isEmpty)
        XCTAssertFalse(controller.showsDiscoveryEmptyState)
        XCTAssertEqual(controller.activeFilterNames, ["Vendor known"])
        controller.clearScopeFilters()
        XCTAssertEqual(controller.filteredHosts.map(\.ip), ["127.0.0.1"])
        XCTAssertFalse(controller.showDeadHosts)
    }

    @MainActor func testLabelsAddedBeforeMACEnrichmentSurviveSnapshotAndCanBeRemoved() async {
        let previous = PersistedStore.loadLabels()
        defer { PersistedStore.saveLabels(previous) }
        let host = Host(ip: "127.0.0.1", mac: "28:6f:b9:00:00:01", status: .alive)
        let controller = await scannedController([host])
        defer { controller.stop() }
        controller.labels = [host.ip: "Desk #work"]
        XCTAssertEqual(controller.makeSnapshot().labels[controller.anchor(for: host)], "Desk #work")
        controller.setLabel("Updated", for: host)
        XCTAssertEqual(controller.label(for: host), "Updated")
        XCTAssertNil(controller.labels[host.ip])
        controller.setLabel("", for: host)
        XCTAssertNil(controller.label(for: host))
    }
    @MainActor func testSavedRangeReplacesImportedTargets() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try "127.0.0.2".write(to: url, atomically: true, encoding: .utf8)
        let controller = ScanController()
        try controller.loadImportedFile(url: url)
        controller.loadSavedRange("127.0.0.1")
        XCTAssertNil(controller.importedTargets)
        XCTAssertEqual(controller.rangeInput, "127.0.0.1")
    }

    @MainActor func testIdenticalSnapshotsIgnoreDeadProbes() async {
        let alive = Host(ip: "127.0.0.1", status: .alive)
        let dead = Host(ip: "127.0.0.2", status: .dead)
        let controller = await scannedController([alive, dead])
        defer { controller.stop() }
        let diff = SnapshotDiff.compute(current: [alive, dead], baseline: controller.makeSnapshot())
        XCTAssertEqual(diff.missingCount, 0)
        XCTAssertEqual(diff.newCount, 0)
        XCTAssertEqual(diff.modifiedCount, 0)
    }

    @MainActor func testComparisonUsesCanonicalMACForRowBadge() async {
        let host = Host(ip: "127.0.0.1", mac: "28:6F:B9:0:0:1", status: .alive)
        let controller = await scannedController([host])
        defer { controller.stop() }
        var baseline = controller.makeSnapshot()
        baseline = ScanSnapshot(version: baseline.version, createdAt: baseline.createdAt,
                                rangeInput: baseline.rangeInput, hosts: [], labels: [:])
        controller.loadComparisonBaseline(baseline)
        XCTAssertEqual(controller.change(for: host), .new)
    }

    @MainActor func testSnapshotReplacementAndRemovalRecomputeComparison() async {
        let previous = PersistedStore.loadLabels()
        defer { PersistedStore.saveLabels(previous) }
        let controller = await scannedController([Host(ip: "127.0.0.1", status: .alive)])
        defer { controller.stop() }
        let oneHost = controller.makeSnapshot()
        let empty = ScanSnapshot(version: oneHost.version, createdAt: oneHost.createdAt,
                                 rangeInput: oneHost.rangeInput, hosts: [], labels: [:])
        controller.loadComparisonBaseline(empty)
        controller.applySnapshot(empty)
        XCTAssertEqual(controller.diff?.newCount, 0)
        controller.applySnapshot(oneHost)
        XCTAssertEqual(controller.diff?.newCount, 1)
        controller.deleteHosts(Set(controller.hosts.map(\.id)))
        XCTAssertEqual(controller.diff?.newCount, 0)
    }

    @MainActor func testExplicitPortTargetsOverrideUnrelatedSelection() async {
        let recorder = ProbeRecorder()
        let hosts = [Host(ip: "127.0.0.1", status: .alive), Host(ip: "127.0.0.2", status: .alive)]
        var operations = ScanController.Operations()
        operations.scan = { _, _ in AsyncStream { stream in
            hosts.forEach { stream.yield(.host($0)) }
            stream.finish()
        } }
        operations.probe = { ip, _ in await recorder.record(ip); return [] }
        let controller = ScanController(operations: operations)
        defer { controller.stop() }
        controller.rangeInput = "127.0.0.1"
        controller.profile = .quick
        controller.start()
        for _ in 0..<200 where controller.isScanning { try? await Task.sleep(for: .milliseconds(5)) }
        controller.selection = [hosts[0].id]
        controller.runPortScan(ports: [80], targetIds: [hosts[1].id])
        for _ in 0..<200 where controller.isScanning { try? await Task.sleep(for: .milliseconds(5)) }
        let probed = await recorder.addresses
        XCTAssertEqual(probed, [hosts[1].ip])
    }

}


private actor ProbeRecorder {
    var addresses: [String] = []
    func record(_ ip: String) { addresses.append(ip) }
}
