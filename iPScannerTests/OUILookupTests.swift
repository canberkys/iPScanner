import XCTest
@testable import iPScanner

final class OUILookupTests: XCTestCase {

    // MARK: - normalizedHex

    func testNormalizedHexUppercases() {
        XCTAssertEqual(OUILookup.normalizedHex("aa:bb:cc:dd:ee:ff"), "AABBCCDDEE")
    }

    func testNormalizedHexPadsSingleDigitSegments() {
        // arp -an output sometimes drops leading zeros: "0:1:2:3:4:5" → "0001020304"
        XCTAssertEqual(OUILookup.normalizedHex("0:1:2:3:4:5"), "0001020304")
    }

    func testNormalizedHexHandlesMixedCase() {
        XCTAssertEqual(OUILookup.normalizedHex("aA:Bb:cC:Dd:eE:Ff"), "AABBCCDDEE")
    }

    func testNormalizedHexReturnsEmptyForShortInput() {
        XCTAssertEqual(OUILookup.normalizedHex("aa:bb:cc"), "")
    }

    // MARK: - 3-tier priority

    func testMASOverridesMAMAndMAL() {
        // Same OUI 12-34-56, MA-S sub-block FFA, MA-M sub-block F, MA-L base.
        let lookup = OUILookup(
            mas: ["123456FFA": "Specific MA-S Vendor"],
            mam: ["1234567": "MA-M Vendor"],
            mal: ["123456": "MA-L Vendor"]
        )
        // MAC where bits 25-36 = FFAxx → must hit MA-S key 123456FFA.
        XCTAssertEqual(lookup.vendor(forMAC: "12:34:56:FF:A1:23"), "Specific MA-S Vendor")
    }

    func testMAMOverridesMAL() {
        let lookup = OUILookup(
            mas: ["123456FFA": "MA-S Vendor"],
            mam: ["1234568": "MA-M Vendor"],
            mal: ["123456": "MA-L Vendor"]
        )
        // MAC bits 25-28 = 8 (sub-prefix length 1) → matches MA-M but not MA-S.
        XCTAssertEqual(lookup.vendor(forMAC: "12:34:56:8A:BC:DE"), "MA-M Vendor")
    }

    func testMALFallbackWhenNoSubBlock() {
        let lookup = OUILookup(
            mas: [:],
            mam: [:],
            mal: ["AABBCC": "Cisco Systems"]
        )
        XCTAssertEqual(lookup.vendor(forMAC: "AA:BB:CC:11:22:33"), "Cisco Systems")
    }

    func testReturnsNilWhenNotInAnyRegistry() {
        let lookup = OUILookup(mas: [:], mam: [:], mal: [:])
        XCTAssertNil(lookup.vendor(forMAC: "AA:BB:CC:DD:EE:FF"))
    }

    func testLookupIsCaseInsensitive() {
        let lookup = OUILookup(
            mas: [:],
            mam: [:],
            mal: ["AABBCC": "Vendor"]
        )
        XCTAssertEqual(lookup.vendor(forMAC: "aa:bb:cc:dd:ee:ff"), "Vendor")
    }

    func testLookupHandlesShortMAC() {
        // MAC with only OUI portion → falls through to MA-L only.
        let lookup = OUILookup(
            mas: ["AABBCCDDE": "Should not match"],
            mam: ["AABBCCD": "Should not match"],
            mal: ["AABBCC": "MA-L Hit"]
        )
        // Just 3 segments → normalizedHex returns "" → empty count < 9 → uses prefix(6) of "" → no match
        XCTAssertNil(lookup.vendor(forMAC: "AA:BB:CC"))
    }
}
