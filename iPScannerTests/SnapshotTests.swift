import XCTest
@testable import iPScanner

final class SnapshotTests: XCTestCase {

    func testEncodeDecodeRoundtrip() throws {
        let snapshot = ScanSnapshot(
            version: ScanSnapshot.currentVersion,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            rangeInput: "192.168.1.0/24",
            hosts: [
                ScanSnapshot.HostRecord(
                    ip: "192.168.1.1",
                    hostname: "router",
                    mac: "AA:BB:CC:DD:EE:FF",
                    vendor: "Test Vendor",
                    rttMs: 1.5,
                    ttl: 64,
                    openPorts: [80, 443],
                    serviceTitle: "Login"
                ),
                ScanSnapshot.HostRecord(
                    ip: "192.168.1.50",
                    hostname: nil,
                    mac: nil,
                    vendor: nil,
                    rttMs: nil,
                    ttl: nil,
                    openPorts: [],
                    serviceTitle: nil
                )
            ],
            labels: ["AA:BB:CC:DD:EE:FF": "My Router"]
        )

        let data = try SnapshotIO.encode(snapshot)
        let decoded = try SnapshotIO.decode(data)

        XCTAssertEqual(decoded.version, ScanSnapshot.currentVersion)
        XCTAssertEqual(decoded.rangeInput, "192.168.1.0/24")
        XCTAssertEqual(decoded.hosts.count, 2)
        XCTAssertEqual(decoded.hosts[0].ip, "192.168.1.1")
        XCTAssertEqual(decoded.hosts[0].hostname, "router")
        XCTAssertEqual(decoded.hosts[0].openPorts, [80, 443])
        XCTAssertEqual(decoded.hosts[0].serviceTitle, "Login")
        XCTAssertNil(decoded.hosts[1].hostname)
        XCTAssertNil(decoded.hosts[1].rttMs)
        XCTAssertEqual(decoded.labels["AA:BB:CC:DD:EE:FF"], "My Router")
    }

    func testEncodedJSONIsHumanReadable() throws {
        let snapshot = ScanSnapshot(
            version: 1,
            createdAt: Date(timeIntervalSince1970: 0),
            rangeInput: "10.0.0.0/30",
            hosts: [],
            labels: [:]
        )
        let data = try SnapshotIO.encode(snapshot)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("\"version\""))
        XCTAssertTrue(str.contains("\"rangeInput\""))
        XCTAssertTrue(str.contains("\"createdAt\""))
        // ISO8601 date format
        XCTAssertTrue(str.contains("1970-01-01"))
        // Pretty-printed (multi-line)
        XCTAssertTrue(str.contains("\n"))
    }

    func testDecodeRejectsGarbage() {
        let garbage = Data("not json".utf8)
        XCTAssertThrowsError(try SnapshotIO.decode(garbage))
    }

    /// Older `.ipscan.json` files (pre-v1.2) were saved without the `ttl` field.
    /// Make sure they still load — TTL should default to nil.
    func testDecodesLegacySnapshotWithoutTTL() throws {
        let legacy = """
        {
          "version" : 1,
          "createdAt" : "2026-04-26T10:00:00Z",
          "rangeInput" : "10.0.0.0/24",
          "hosts" : [
            {
              "ip" : "10.0.0.1",
              "hostname" : "router",
              "mac" : "AA:BB:CC:DD:EE:FF",
              "vendor" : "Cisco",
              "rttMs" : 1.2,
              "openPorts" : [80, 443],
              "serviceTitle" : null
            }
          ],
          "labels" : {}
        }
        """.data(using: .utf8)!

        let decoded = try SnapshotIO.decode(legacy)
        XCTAssertEqual(decoded.hosts.count, 1)
        XCTAssertEqual(decoded.hosts[0].ip, "10.0.0.1")
        XCTAssertNil(decoded.hosts[0].ttl, "Missing TTL field should decode to nil")
    }

    func testDefaultFileNamePattern() {
        let name = SnapshotIO.defaultFileName()
        XCTAssertTrue(name.hasPrefix("iPScanner-"))
        XCTAssertTrue(name.hasSuffix(".ipscan.json"))
        // Date pattern yyyy-MM-dd-HHmm should produce 15 chars between hyphens
        XCTAssertGreaterThan(name.count, 20)
    }
}
