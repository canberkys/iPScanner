import XCTest
@testable import iPScanner

final class ICMPSweeperTests: XCTestCase {
    func testEchoRequestHasValidChecksum() {
        let p = ICMPSweeper.buildEchoRequest(identifier: 0x1234, sequence: 7)
        XCTAssertEqual(p[0], 8)
        XCTAssertEqual(Array(p[4...7]), [0x12, 0x34, 0x00, 0x07])
        // A packet whose checksum field is correct sums to zero.
        XCTAssertEqual(ICMPSweeper.checksum(p), 0)
    }

    func testParsesReplyWithAndWithoutIPHeader() {
        let reply: [UInt8] = [0, 0, 0, 0, 0x12, 0x34, 0x00, 0x09]
        XCTAssertEqual(ICMPSweeper.parseReply(reply)?.sequence, 9)
        XCTAssertNil(ICMPSweeper.parseReply(reply)?.ttl)

        var ip = [UInt8](repeating: 0, count: 20)
        ip[0] = 0x45; ip[8] = 64
        let withHeader = ICMPSweeper.parseReply(ip + reply)
        XCTAssertEqual(withHeader?.ttl, 64)
        XCTAssertEqual(withHeader?.sequence, 9)
        XCTAssertNil(ICMPSweeper.parseReply([8, 0, 0, 0, 0, 0, 0, 0]))  // request, not reply
    }

    func testSweepFindsLoopback() async throws {
        let result = await ICMPSweeper.sweep(["127.0.0.1"], waitMs: 500)
        let replies = try XCTUnwrap(result, "ICMP datagram socket unavailable")
        XCTAssertNotNil(replies["127.0.0.1"])
    }
}
