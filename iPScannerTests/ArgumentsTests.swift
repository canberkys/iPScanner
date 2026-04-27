import XCTest
@testable import iPScanner

final class ArgumentsTests: XCTestCase {

    func testParsesPositionalRange() throws {
        let args = try Arguments.parse(["10.0.0.0/24"])
        XCTAssertEqual(args.range, "10.0.0.0/24")
        XCTAssertNil(args.inputFile)
        XCTAssertEqual(args.profile, .standard)
        XCTAssertEqual(args.format, .json)
    }

    func testAcceptsLeadingScanSubcommand() throws {
        let args = try Arguments.parse(["scan", "10.0.0.0/24"])
        XCTAssertEqual(args.range, "10.0.0.0/24")
    }

    func testParsesProfileFlag() throws {
        let args = try Arguments.parse(["10.0.0.0/24", "--profile", "deep"])
        XCTAssertEqual(args.profile, .deep)
    }

    func testInvalidProfileRejected() {
        XCTAssertThrowsError(try Arguments.parse(["10.0.0.0/24", "--profile", "extreme"])) { err in
            guard case Arguments.ParseError.invalidValue(let flag, let value, _) = err else {
                return XCTFail("expected .invalidValue, got \(err)")
            }
            XCTAssertEqual(flag, "--profile")
            XCTAssertEqual(value, "extreme")
        }
    }

    func testParsesPorts() throws {
        let args = try Arguments.parse(["10.0.0.0/24", "--ports", "22,80,8000-8002"])
        XCTAssertEqual(args.ports, [22, 80, 8000, 8001, 8002])
    }

    func testInvalidPortsRejected() {
        XCTAssertThrowsError(try Arguments.parse(["10.0.0.0/24", "--ports", "abc"])) { err in
            guard case Arguments.ParseError.invalidValue = err else {
                return XCTFail("expected .invalidValue, got \(err)")
            }
        }
    }

    func testParsesFormat() throws {
        for raw in ["json", "csv", "txt", "ip-port"] {
            let args = try Arguments.parse(["10.0.0.0/24", "--format", raw])
            XCTAssertEqual(args.format.rawValue, raw)
        }
    }

    func testInvalidFormatRejected() {
        XCTAssertThrowsError(try Arguments.parse(["10.0.0.0/24", "--format", "yaml"]))
    }

    func testParsesInputFile() throws {
        let args = try Arguments.parse(["--input", "/tmp/targets.txt"])
        XCTAssertEqual(args.inputFile, "/tmp/targets.txt")
        XCTAssertNil(args.range)
    }

    func testFlagsCanAppearAnywhere() throws {
        let args = try Arguments.parse(["--profile", "quick", "10.0.0.0/24", "--format", "csv"])
        XCTAssertEqual(args.range, "10.0.0.0/24")
        XCTAssertEqual(args.profile, .quick)
        XCTAssertEqual(args.format, .csv)
    }

    func testFetchBannersFlag() throws {
        let args = try Arguments.parse(["10.0.0.0/24", "--fetch-banners"])
        XCTAssertTrue(args.fetchBanners)
    }

    func testQuietFlag() throws {
        let args = try Arguments.parse(["10.0.0.0/24", "--quiet"])
        XCTAssertTrue(args.quiet)
    }

    func testHelpFlag() throws {
        let args = try Arguments.parse(["--help"])
        XCTAssertTrue(args.help)
    }

    func testMissingValueAfterFlagRejected() {
        XCTAssertThrowsError(try Arguments.parse(["10.0.0.0/24", "--profile"])) { err in
            guard case Arguments.ParseError.missingValue(let flag) = err else {
                return XCTFail("expected .missingValue, got \(err)")
            }
            XCTAssertEqual(flag, "--profile")
        }
    }

    func testUnknownFlagRejected() {
        XCTAssertThrowsError(try Arguments.parse(["10.0.0.0/24", "--turbo"])) { err in
            guard case Arguments.ParseError.unknownFlag = err else {
                return XCTFail("expected .unknownFlag, got \(err)")
            }
        }
    }

    func testTwoPositionalsRejected() {
        XCTAssertThrowsError(try Arguments.parse(["10.0.0.0/24", "192.168.1.0/24"])) { err in
            guard case Arguments.ParseError.unexpectedArgument = err else {
                return XCTFail("expected .unexpectedArgument, got \(err)")
            }
        }
    }

    func testOutputPath() throws {
        let args = try Arguments.parse(["10.0.0.0/24", "--output", "/tmp/scan.json"])
        XCTAssertEqual(args.output, "/tmp/scan.json")
    }
}
