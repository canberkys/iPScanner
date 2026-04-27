import XCTest
@testable import iPScanner

final class NetBIOSResolverTests: XCTestCase {

    // MARK: - Wire-format build

    func testQueryPacketLayout() {
        let data = NetBIOSResolver.buildQuery(transactionID: 0x1234)
        XCTAssertEqual(data.count, 50, "NBSTAT wildcard query is always 50 bytes")

        let bytes = Array(data)
        // Header: txn id high/low
        XCTAssertEqual(bytes[0], 0x12)
        XCTAssertEqual(bytes[1], 0x34)
        // Flags (standard query, no recursion)
        XCTAssertEqual(bytes[2], 0x00)
        XCTAssertEqual(bytes[3], 0x00)
        // QDCOUNT = 1
        XCTAssertEqual(bytes[4], 0x00)
        XCTAssertEqual(bytes[5], 0x01)
        // ANCOUNT, NSCOUNT, ARCOUNT all 0
        XCTAssertEqual(Array(bytes[6...11]), [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        // Name length byte
        XCTAssertEqual(bytes[12], 0x20)
        // Encoded wildcard starts with 'C' 'K' (for '*' = 0x2A)
        XCTAssertEqual(bytes[13], 0x43) // 'C'
        XCTAssertEqual(bytes[14], 0x4B) // 'K'
        // The next 30 bytes encode 15 NUL bytes as "AA" pairs
        for offset in 15..<45 {
            XCTAssertEqual(bytes[offset], 0x41, "byte \(offset) should be 'A'")
        }
        // Null root terminator
        XCTAssertEqual(bytes[45], 0x00)
        // QTYPE = NBSTAT (0x0021)
        XCTAssertEqual(bytes[46], 0x00)
        XCTAssertEqual(bytes[47], 0x21)
        // QCLASS = IN (0x0001)
        XCTAssertEqual(bytes[48], 0x00)
        XCTAssertEqual(bytes[49], 0x01)
    }

    // MARK: - Response parsing

    /// Builds a synthetic NBSTAT response containing the given list of
    /// (name, type, isGroup) entries plus a trailing 6-byte MAC.
    private func makeResponse(names: [(String, UInt8, Bool)]) -> Data {
        var data = Data()
        // Header: txn id, response flags, qd=1, an=1
        data.append(contentsOf: [0x12, 0x34])
        data.append(contentsOf: [0x84, 0x00])
        data.append(contentsOf: [0x00, 0x01])
        data.append(contentsOf: [0x00, 0x01])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // Echoed question name (encoded wildcard)
        data.append(0x20)
        data.append(contentsOf: Array(("CK" + String(repeating: "AA", count: 15)).utf8))
        data.append(0x00)
        data.append(contentsOf: [0x00, 0x21, 0x00, 0x01])

        // Answer record: compression pointer back to question name
        data.append(contentsOf: [0xC0, 0x0C])
        data.append(contentsOf: [0x00, 0x21, 0x00, 0x01])  // type / class
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // ttl
        let rdataLength = UInt16(1 + names.count * 18 + 6)  // numNames + names + MAC
        data.append(UInt8(rdataLength >> 8))
        data.append(UInt8(rdataLength & 0xFF))

        // RDATA
        data.append(UInt8(names.count))
        for (name, typeByte, isGroup) in names {
            var nameBytes = Array(name.padding(toLength: 15, withPad: " ", startingAt: 0).utf8)
            nameBytes = Array(nameBytes.prefix(15))
            data.append(contentsOf: nameBytes)
            data.append(typeByte)
            data.append(isGroup ? 0x80 : 0x00)
            data.append(0x00)
        }
        // MAC stub
        data.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        return data
    }

    func testParseExtractsComputerName() {
        let data = makeResponse(names: [
            ("MYPC", 0x00, false),
            ("WORKGROUP", 0x00, true)
        ])
        let result = NetBIOSResolver.parseResponse(data)
        XCTAssertEqual(result?.computerName, "MYPC")
        XCTAssertEqual(result?.workgroup, "WORKGROUP")
    }

    func testParseUsesType1BAsDomain() {
        let data = makeResponse(names: [
            ("DC01", 0x00, false),
            ("CORP", 0x1B, false)  // domain master browser
        ])
        let result = NetBIOSResolver.parseResponse(data)
        XCTAssertEqual(result?.computerName, "DC01")
        XCTAssertEqual(result?.workgroup, "CORP")
    }

    func testParseRejectsTooShort() {
        XCTAssertNil(NetBIOSResolver.parseResponse(Data([0x00, 0x01, 0x02])))
    }

    func testParseReturnsNilWhenNoUsefulNames() {
        let data = makeResponse(names: [
            ("__MSBROWSE__", 0x01, true)  // ignored types
        ])
        XCTAssertNil(NetBIOSResolver.parseResponse(data))
    }
}
