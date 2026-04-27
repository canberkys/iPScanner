import XCTest
@testable import iPScanner

final class ScanRangeTests: XCTestCase {

    // MARK: - CIDR

    func testCIDR24() {
        let r = ScanRange(cidr: "10.0.0.0/24")
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.hostCount, 254)
        XCTAssertEqual(r?.addresses.first, "10.0.0.1")
        XCTAssertEqual(r?.addresses.last, "10.0.0.254")
    }

    func testCIDR30() {
        let r = ScanRange(cidr: "10.0.0.0/30")
        XCTAssertEqual(r?.hostCount, 2)
        XCTAssertEqual(r?.addresses, ["10.0.0.1", "10.0.0.2"])
    }

    func testCIDR31() {
        // RFC 3021: /31 carries no network/broadcast — both addresses usable.
        let r = ScanRange(cidr: "10.0.0.0/31")
        XCTAssertEqual(r?.hostCount, 2)
        XCTAssertEqual(r?.addresses, ["10.0.0.0", "10.0.0.1"])
    }

    func testCIDR32() {
        let r = ScanRange(cidr: "10.0.0.5/32")
        XCTAssertEqual(r?.hostCount, 1)
        XCTAssertEqual(r?.addresses, ["10.0.0.5"])
    }

    func testCIDR16() {
        let r = ScanRange(cidr: "172.16.0.0/16")
        XCTAssertEqual(r?.hostCount, 65534)
        XCTAssertEqual(r?.addresses.first, "172.16.0.1")
        XCTAssertEqual(r?.addresses.last, "172.16.255.254")
    }

    func testCIDRInvalid() {
        XCTAssertNil(ScanRange(cidr: "10.0.0.0/33"))
        XCTAssertNil(ScanRange(cidr: "10.0.0.0"))
        XCTAssertNil(ScanRange(cidr: "not-an-ip/24"))
        XCTAssertNil(ScanRange(cidr: "10.0.0.0/abc"))
        XCTAssertNil(ScanRange(cidr: "999.0.0.0/24"))
    }

    // MARK: - Range

    func testRangeBasic() {
        let r = ScanRange(range: "192.168.1.10-192.168.1.20")
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.hostCount, 11)
        XCTAssertEqual(r?.addresses.first, "192.168.1.10")
        XCTAssertEqual(r?.addresses.last, "192.168.1.20")
    }

    func testRangeCrossSubnet() {
        // Cross /24 boundary (subnet "wrap" inside contiguous numeric range).
        let r = ScanRange(range: "192.168.0.250-192.168.1.5")
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.hostCount, 12)
    }

    func testRangeWithSpaces() {
        let r = ScanRange(range: "10.0.0.1 - 10.0.0.5")
        XCTAssertEqual(r?.hostCount, 5)
    }

    func testRangeInvalid() {
        XCTAssertNil(ScanRange(range: "10.0.0.10-10.0.0.5"))   // hi < lo
        XCTAssertNil(ScanRange(range: "10.0.0.0"))             // missing dash
        XCTAssertNil(ScanRange(range: "not-ip-not-ip"))
        XCTAssertNil(ScanRange(range: "10.0.0.1-"))            // missing hi
    }

    // MARK: - parse (auto-detect cidr/range)

    func testParseDispatchesCorrectly() {
        XCTAssertEqual(ScanRange.parse("10.0.0.0/30")?.hostCount, 2)
        XCTAssertEqual(ScanRange.parse("10.0.0.1-10.0.0.3")?.hostCount, 3)
        XCTAssertNil(ScanRange.parse("garbage"))
    }

    // MARK: - parseAll (multi-range, comma-separated)

    func testParseAllMultiple() {
        let result = ScanRange.parseAll("10.0.0.0/24, 192.168.1.0/30")
        XCTAssertNil(result.firstInvalidIndex)
        XCTAssertEqual(result.ranges.count, 2)
    }

    func testParseAllReportsBadChunkIndex() {
        let result = ScanRange.parseAll("10.0.0.0/24, garbage, 192.168.1.0/24")
        XCTAssertEqual(result.firstInvalidIndex, 2)
    }

    func testParseAllEmpty() {
        let result = ScanRange.parseAll("")
        XCTAssertTrue(result.ranges.isEmpty)
        XCTAssertNil(result.firstInvalidIndex)
    }

    func testParseAllSkipsEmptyChunks() {
        // Trailing comma or double commas don't error.
        let result = ScanRange.parseAll("10.0.0.0/30,, ")
        XCTAssertEqual(result.ranges.count, 1)
        XCTAssertNil(result.firstInvalidIndex)
    }

    // MARK: - uniqueAddresses

    func testUniqueAddressesDeduplicates() {
        let r1 = ScanRange(cidr: "10.0.0.0/29")!  // hosts 10.0.0.1-10.0.0.6
        let r2 = ScanRange(range: "10.0.0.5-10.0.0.10")!
        let unique = ScanRange.uniqueAddresses([r1, r2])
        XCTAssertEqual(unique.count, 10)
        XCTAssertEqual(unique.first, "10.0.0.1")
        XCTAssertEqual(unique.last, "10.0.0.10")
    }

    func testUniqueAddressesSorted() {
        let r1 = ScanRange(range: "10.0.0.5-10.0.0.6")!
        let r2 = ScanRange(range: "10.0.0.1-10.0.0.2")!
        let unique = ScanRange.uniqueAddresses([r1, r2])
        XCTAssertEqual(unique, ["10.0.0.1", "10.0.0.2", "10.0.0.5", "10.0.0.6"])
    }

    // MARK: - IPv4 helpers

    func testIPv4UInt32Conversion() {
        XCTAssertEqual(IPv4.uint32(from: "0.0.0.0"), 0)
        XCTAssertEqual(IPv4.uint32(from: "255.255.255.255"), UInt32.max)
        XCTAssertEqual(IPv4.uint32(from: "192.168.1.1"), 0xC0A80101)
        XCTAssertNil(IPv4.uint32(from: "999.0.0.0"))
        XCTAssertNil(IPv4.uint32(from: "1.2.3"))
        XCTAssertNil(IPv4.uint32(from: ""))
    }

    func testIPv4StringConversion() {
        XCTAssertEqual(IPv4.string(from: 0), "0.0.0.0")
        XCTAssertEqual(IPv4.string(from: UInt32.max), "255.255.255.255")
        XCTAssertEqual(IPv4.string(from: 0xC0A80101), "192.168.1.1")
    }

    func testIPv4Roundtrip() {
        for ip in ["0.0.0.0", "10.224.5.1", "172.16.0.1", "192.168.1.254", "255.255.255.255"] {
            let value = IPv4.uint32(from: ip)!
            XCTAssertEqual(IPv4.string(from: value), ip)
        }
    }
}
