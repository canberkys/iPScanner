import XCTest
@testable import iPScanner

final class UpdateCheckerTests: XCTestCase {

    // MARK: - parseVersion

    func testParseStripsLeadingV() {
        XCTAssertEqual(UpdateChecker.parseVersion("v1.2.0"), [1, 2, 0])
        XCTAssertEqual(UpdateChecker.parseVersion("V1.2.0"), [1, 2, 0])
    }

    func testParseHandlesPlainSemver() {
        XCTAssertEqual(UpdateChecker.parseVersion("1.2.3"), [1, 2, 3])
    }

    func testParseDropsPreReleaseSuffix() {
        XCTAssertEqual(UpdateChecker.parseVersion("1.2.0-beta.1"), [1, 2, 0])
        XCTAssertEqual(UpdateChecker.parseVersion("1.2.0+build.42"), [1, 2, 0])
    }

    func testParseTrimsWhitespace() {
        XCTAssertEqual(UpdateChecker.parseVersion("  1.0.0  "), [1, 0, 0])
    }

    // MARK: - isNewer

    func testIsNewerStrict() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.0", than: "1.1.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.99"), "should compare numerically, not lexically")
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.99.99"))
    }

    func testEqualVersionsAreNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0", than: "1.2.0"))
    }

    func testTrailingZeroIsEqual() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0", than: "1.2"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2.0"))
    }

    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.3", than: "1.2.4"))
    }

    func testHandlesVPrefixOnEitherSide() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.2.0", than: "1.1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.2.0", than: "v1.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("v1.0.0", than: "v1.0.0"))
    }
}
