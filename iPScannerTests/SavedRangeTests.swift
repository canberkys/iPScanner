import XCTest
@testable import iPScanner

final class SavedRangeTests: XCTestCase {

    func testDisplayTitleWithName() {
        let r = SavedRange(range: "10.0.0.0/24", name: "Home")
        XCTAssertEqual(r.displayTitle, "Home")
    }

    func testDisplayTitleFallsBackToRange() {
        let r = SavedRange(range: "10.0.0.0/24", name: nil)
        XCTAssertEqual(r.displayTitle, "10.0.0.0/24")
    }

    func testEmptyNameFallsBackToRange() {
        let r = SavedRange(range: "10.0.0.0/24", name: "")
        XCTAssertEqual(r.displayTitle, "10.0.0.0/24")
    }

    func testIDIsRange() {
        let r = SavedRange(range: "10.0.0.0/24", name: "Home")
        XCTAssertEqual(r.id, "10.0.0.0/24")
    }

    func testCodableRoundtrip() throws {
        let original = [
            SavedRange(range: "10.0.0.0/24", name: "Home"),
            SavedRange(range: "192.168.1.0/24", name: nil),
            SavedRange(range: "172.16.0.0/16", name: "Office VLAN")
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([SavedRange].self, from: data)
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].name, "Home")
        XCTAssertNil(decoded[1].name)
        XCTAssertEqual(decoded[2].displayTitle, "Office VLAN")
    }

    func testHashable() {
        let a = SavedRange(range: "10.0.0.0/24", name: "Home")
        let b = SavedRange(range: "10.0.0.0/24", name: "Home")
        let c = SavedRange(range: "10.0.0.0/24", name: "Different")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
