import XCTest
@testable import iPScanner

final class SubnetCalculatorTests: XCTestCase {

    func testStandardClassC() {
        let s = SubnetCalculator.summarize("10.0.0.0/24")
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.network, "10.0.0.0")
        XCTAssertEqual(s?.broadcast, "10.0.0.255")
        XCTAssertEqual(s?.firstHost, "10.0.0.1")
        XCTAssertEqual(s?.lastHost, "10.0.0.254")
        XCTAssertEqual(s?.hostCount, 254)
        XCTAssertEqual(s?.netmask, "255.255.255.0")
        XCTAssertEqual(s?.wildcard, "0.0.0.255")
    }

    func testHostBitsMaskedToNetwork() {
        let s = SubnetCalculator.summarize("10.0.0.42/24")
        XCTAssertEqual(s?.network, "10.0.0.0")
        XCTAssertEqual(s?.broadcast, "10.0.0.255")
    }

    func testSlash30PointToPoint() {
        let s = SubnetCalculator.summarize("192.168.1.0/30")
        XCTAssertEqual(s?.network, "192.168.1.0")
        XCTAssertEqual(s?.broadcast, "192.168.1.3")
        XCTAssertEqual(s?.firstHost, "192.168.1.1")
        XCTAssertEqual(s?.lastHost, "192.168.1.2")
        XCTAssertEqual(s?.hostCount, 2)
    }

    func testSlash31RFC3021() {
        let s = SubnetCalculator.summarize("192.168.1.0/31")
        XCTAssertEqual(s?.firstHost, "192.168.1.0")
        XCTAssertEqual(s?.lastHost, "192.168.1.1")
        XCTAssertEqual(s?.hostCount, 2)
    }

    func testSlash32Single() {
        let s = SubnetCalculator.summarize("8.8.8.8/32")
        XCTAssertEqual(s?.firstHost, "8.8.8.8")
        XCTAssertEqual(s?.lastHost, "8.8.8.8")
        XCTAssertEqual(s?.hostCount, 1)
        XCTAssertEqual(s?.netmask, "255.255.255.255")
    }

    func testSlash16Class() {
        let s = SubnetCalculator.summarize("172.16.0.0/16")
        XCTAssertEqual(s?.broadcast, "172.16.255.255")
        XCTAssertEqual(s?.hostCount, 65534)
        XCTAssertEqual(s?.netmask, "255.255.0.0")
    }

    func testInvalidInputRejected() {
        XCTAssertNil(SubnetCalculator.summarize("garbage"))
        XCTAssertNil(SubnetCalculator.summarize("10.0.0.0"))         // no slash
        XCTAssertNil(SubnetCalculator.summarize("10.0.0.0/33"))      // out of range
        XCTAssertNil(SubnetCalculator.summarize("999.0.0.0/24"))     // bad octet
    }

    func testTrimsWhitespace() {
        let s = SubnetCalculator.summarize("  10.0.0.0/24  ")
        XCTAssertEqual(s?.network, "10.0.0.0")
    }
}
