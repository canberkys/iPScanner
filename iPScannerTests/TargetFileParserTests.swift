import XCTest
@testable import iPScanner

final class TargetFileParserTests: XCTestCase {

    func testParsesIndividualIPs() {
        let result = TargetFileParser.parse(text: """
        10.0.0.1
        10.0.0.2
        10.0.0.3
        """)
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.2", "10.0.0.3"])
        XCTAssertTrue(result.invalidLines.isEmpty)
        XCTAssertEqual(result.parsedTokenCount, 3)
    }

    func testParsesCIDR() {
        let result = TargetFileParser.parse(text: "10.0.0.0/30")
        // /30 → 4 addresses, but ScanRange treats /30 as network+1 to broadcast-1 (2 hosts)
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.2"])
    }

    func testParsesRange() {
        let result = TargetFileParser.parse(text: "192.168.1.10-192.168.1.12")
        XCTAssertEqual(result.targets, ["192.168.1.10", "192.168.1.11", "192.168.1.12"])
    }

    func testParsesMixedTokensInLine() {
        let result = TargetFileParser.parse(text: "10.0.0.1, 10.0.0.5-10.0.0.6, 192.168.1.0/30")
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.5", "10.0.0.6", "192.168.1.1", "192.168.1.2"])
        XCTAssertEqual(result.parsedTokenCount, 3)
    }

    func testIgnoresBlankLinesAndComments() {
        let result = TargetFileParser.parse(text: """

        # printers
        10.0.0.1

        # servers
        10.0.0.5

        """)
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.5"])
    }

    func testDeduplicatesAcrossLines() {
        let result = TargetFileParser.parse(text: """
        10.0.0.1
        10.0.0.1
        10.0.0.0/30
        """)
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.2"])
    }

    func testReportsInvalidLines() {
        let result = TargetFileParser.parse(text: """
        10.0.0.1
        not-an-ip
        300.300.300.300
        10.0.0.5
        """)
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.5"])
        XCTAssertEqual(result.invalidLines.count, 2)
        XCTAssertEqual(result.invalidLines.map(\.content).sorted(), ["300.300.300.300", "not-an-ip"])
    }

    func testInvalidTokenInMixedLineDoesNotKillValidOnes() {
        let result = TargetFileParser.parse(text: "10.0.0.1, not-valid, 10.0.0.5")
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.5"])
        XCTAssertEqual(result.invalidLines.count, 1)
        XCTAssertEqual(result.invalidLines.first?.content, "not-valid")
    }

    func testEmptyTextReturnsNoTargets() {
        let result = TargetFileParser.parse(text: "")
        XCTAssertTrue(result.targets.isEmpty)
        XCTAssertTrue(result.invalidLines.isEmpty)
    }

    func testCarriageReturnLineEndings() {
        // Windows-saved files use CRLF
        let result = TargetFileParser.parse(text: "10.0.0.1\r\n10.0.0.2\r\n")
        XCTAssertEqual(result.targets, ["10.0.0.1", "10.0.0.2"])
    }
}
