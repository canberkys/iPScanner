import XCTest
@testable import iPScanner

final class PortScannerTests: XCTestCase {

    // MARK: - parsePorts

    func testParseSingle() {
        XCTAssertEqual(PortScanner.parsePorts("80"), [80])
    }

    func testParseMultiple() {
        XCTAssertEqual(PortScanner.parsePorts("80, 443, 8080"), [80, 443, 8080])
    }

    func testParseRange() {
        XCTAssertEqual(PortScanner.parsePorts("80-82"), [80, 81, 82])
    }

    func testParseMixed() {
        XCTAssertEqual(PortScanner.parsePorts("22, 80-82, 443"), [22, 80, 81, 82, 443])
    }

    func testParseDeduplicates() {
        XCTAssertEqual(PortScanner.parsePorts("80, 80, 443"), [80, 443])
    }

    func testParseSorted() {
        XCTAssertEqual(PortScanner.parsePorts("443, 22, 80"), [22, 80, 443])
    }

    func testParseWithSpaces() {
        XCTAssertEqual(PortScanner.parsePorts("  22 , 80 - 82 , 443  "), [22, 80, 81, 82, 443])
    }

    func testParseInvalid() {
        XCTAssertNil(PortScanner.parsePorts("garbage"))
        XCTAssertNil(PortScanner.parsePorts("80-50"))   // hi < lo
        XCTAssertNil(PortScanner.parsePorts("0"))        // out of range
        XCTAssertNil(PortScanner.parsePorts("65536"))    // out of range
        XCTAssertNil(PortScanner.parsePorts("80, abc"))
    }

    func testParseEmpty() {
        XCTAssertNil(PortScanner.parsePorts(""))
        XCTAssertNil(PortScanner.parsePorts("   "))
        XCTAssertNil(PortScanner.parsePorts(",,"))
    }

    func testParseFullRange() {
        let result = PortScanner.parsePorts("1-1024")
        XCTAssertEqual(result?.count, 1024)
        XCTAssertEqual(result?.first, 1)
        XCTAssertEqual(result?.last, 1024)
    }

    // MARK: - serviceName

    func testServiceNameWellKnown() {
        XCTAssertEqual(PortScanner.serviceName(for: 22), "ssh")
        XCTAssertEqual(PortScanner.serviceName(for: 80), "http")
        XCTAssertEqual(PortScanner.serviceName(for: 443), "https")
        XCTAssertEqual(PortScanner.serviceName(for: 445), "smb")
        XCTAssertEqual(PortScanner.serviceName(for: 9100), "printer")
        XCTAssertEqual(PortScanner.serviceName(for: 3389), "rdp")
        XCTAssertEqual(PortScanner.serviceName(for: 5900), "vnc")
    }

    func testServiceNameUnknown() {
        XCTAssertNil(PortScanner.serviceName(for: 12345))
        XCTAssertNil(PortScanner.serviceName(for: 7))
    }

    // MARK: - formatList

    func testFormatListWithKnownPorts() {
        XCTAssertEqual(PortScanner.formatList([80, 443]), "80 (http), 443 (https)")
    }

    func testFormatListWithUnknownPort() {
        XCTAssertEqual(PortScanner.formatList([12345]), "12345")
    }

    func testFormatListMixed() {
        XCTAssertEqual(PortScanner.formatList([22, 12345, 443]), "22 (ssh), 12345, 443 (https)")
    }

    func testFormatListEmpty() {
        XCTAssertEqual(PortScanner.formatList([]), "")
    }
}
