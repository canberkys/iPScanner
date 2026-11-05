import XCTest
@testable import iPScanner

final class HostNamesTests: XCTestCase {
    func testPrefersDNSThenMDNSThenNetBIOS() {
        XCTAssertEqual(HostNames.preferred(dns: "router.lan", mdns: "m", netbios: "N"), "router.lan")
        XCTAssertEqual(HostNames.preferred(dns: nil, mdns: "mac-mini", netbios: "N"), "mac-mini")
        XCTAssertEqual(HostNames.preferred(dns: "", mdns: " ", netbios: "NAS01"), "NAS01")
        XCTAssertNil(HostNames.preferred(dns: nil, mdns: nil, netbios: nil))
    }

    func testMDNSDeviceNameStripsWorkstationMACSuffix() {
        let records = [
            MDNSDiscovery.ServiceRecord(displayType: "SSH", serviceType: "_ssh._tcp", name: "Friendly Name", ip: "10.0.0.5"),
            MDNSDiscovery.ServiceRecord(displayType: "Workstation", serviceType: "_workstation._tcp", name: "example-host [aa:bb:cc:dd:ee:ff]", ip: "10.0.0.5")
        ]
        XCTAssertEqual(MDNSDiscovery.deviceName(from: records), "example-host")
        XCTAssertNil(MDNSDiscovery.deviceName(from: []))
    }
}

final class MDNSReverseResolverTests: XCTestCase {
    func testQueryEncodesReversedAddress() throws {
        let q = try XCTUnwrap(MDNSReverseResolver.buildQuery(for: "192.168.4.29"))
        XCTAssertEqual(Array(q[12..<16]), [2, 0x32, 0x39, 1])  // "29" label
        XCTAssertNil(MDNSReverseResolver.buildQuery(for: "not-an-ip"))
    }

    func testParsesPTRAnswerWithCompressedName() {
        var d = Data(MDNSReverseResolver.buildQuery(for: "10.0.0.5")!)
        d[2] = 0x84; d[7] = 1  // response flags, ANCOUNT = 1
        d.append(contentsOf: [0xC0, 0x0C, 0x00, 0x0C, 0x00, 0x01, 0, 0, 0, 120])
        let name: [UInt8] = [7] + Array("example".utf8) + [5] + Array("local".utf8) + [0]
        d.append(contentsOf: [0x00, UInt8(name.count)] + name)
        XCTAssertEqual(MDNSReverseResolver.parseResponse(d), "example")
        XCTAssertNil(MDNSReverseResolver.parseResponse(Data([1, 2, 3])))
        XCTAssertNil(MDNSReverseResolver.clean("MDNSHOSTNAME.local"))
        XCTAssertEqual(MDNSReverseResolver.clean("host.local"), "host")
    }
}

final class IdentificationTests: XCTestCase {
    private func rec(_ type: String, _ name: String, _ txt: [String: String] = [:]) -> MDNSDiscovery.ServiceRecord {
        MDNSDiscovery.ServiceRecord(displayType: "x", serviceType: type, name: name, ip: "10.0.0.5", txt: txt)
    }

    func testIdentificationCombinesModelAndPrinter() {
        let records = [
            rec("_device-info._tcp", "host", ["model": "Macmini9,1"]),
            rec("_ipp._tcp", "Example Printer [ABC123]")
        ]
        XCTAssertEqual(MDNSDiscovery.identification(from: records), "Macmini9,1, Example Printer")
        XCTAssertNil(MDNSDiscovery.identification(from: []))
    }

    func testIdentificationReadsAirPlayAndRAOPModels() {
        let records = [
            rec("_airplay._tcp", "x", ["model": "Mac16,10"]),
            rec("_raop._tcp", "y", ["am": "Mac16,10"])
        ]
        XCTAssertEqual(MDNSDiscovery.identification(from: records), "Mac16,10")
    }

    func testVendorFallbacks() {
        XCTAssertEqual(HostNames.vendor(registered: "Acme", names: ["mac-mini"], serviceTypes: []), "Acme")
        XCTAssertEqual(HostNames.vendor(registered: nil, names: ["Justins-Mac-Studio"], serviceTypes: []), "Apple, Inc.")
        XCTAssertEqual(HostNames.vendor(registered: nil, names: ["MAC-D89EFA"], serviceTypes: []), "Apple, Inc.")
        XCTAssertEqual(HostNames.vendor(registered: nil, names: [], serviceTypes: ["_companion-link._tcp"]), "Apple, Inc.")
        XCTAssertNil(HostNames.vendor(registered: nil, names: ["truenas"], serviceTypes: ["_ssh._tcp"]))
    }
}

final class IPv6NeighborsTests: XCTestCase {
    func testParsesNeighborTableAndSkipsIncomplete() {
        let out = """
        Neighbor                                Linklayer Address  Netif Expire    St Flgs Prbs
        2001:db8::1                             8a:ad:b:d7:d:91      en0 17h30m52s S
        fe80::1%en0                             8a:ad:b:d7:d:91      en0 1s        D
        2001:db8::2                             (incomplete)         en0 expired   N
        """
        let result = IPv6Neighbors.parse(out)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.values.first, ["2001:db8::1", "fe80::1"])
    }

    func testLocalGlobalSplitAndSummary() {
        XCTAssertTrue(IPv6Neighbors.isLocal("fe80::1"))
        XCTAssertTrue(IPv6Neighbors.isLocal("fd11:f419::1"))
        XCTAssertFalse(IPv6Neighbors.isLocal("2606:a300::1"))
        XCTAssertEqual(IPv6Neighbors.summary(["a::1", "a::2"]), "a::1 (+1)")
        XCTAssertNil(IPv6Neighbors.summary([]))
    }
}
