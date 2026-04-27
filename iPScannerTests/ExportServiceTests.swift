import XCTest
@testable import iPScanner

final class ExportServiceTests: XCTestCase {

    private func makeRow(
        ip: String = "10.0.0.1",
        label: String? = nil,
        hostname: String? = nil,
        mac: String? = nil,
        vendor: String? = nil,
        rttMs: Double? = nil,
        openPorts: [Int] = []
    ) -> ExportService.Row {
        ExportService.Row(
            ip: ip, label: label, hostname: hostname, mac: mac,
            vendor: vendor, rttMs: rttMs, openPorts: openPorts
        )
    }

    func testCSVHeader() {
        let csv = ExportService.csv(rows: [])
        XCTAssertTrue(csv.hasPrefix("IP,Label,Hostname,MAC,Vendor,RTT (ms),Open Ports"))
    }

    func testCSVBasic() {
        let csv = ExportService.csv(rows: [
            makeRow(
                label: "Router",
                hostname: "hgw.local",
                mac: "AA:BB:CC:DD:EE:FF",
                vendor: "Vendor Inc",
                rttMs: 1.5,
                openPorts: [80, 443]
            )
        ])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1], "10.0.0.1,Router,hgw.local,AA:BB:CC:DD:EE:FF,Vendor Inc,1.5,80;443")
    }

    func testCSVEscapesComma() {
        let csv = ExportService.csv(rows: [
            makeRow(label: "Vendor Inc, Co.")
        ])
        XCTAssertTrue(csv.contains("\"Vendor Inc, Co.\""))
    }

    func testCSVEscapesQuotes() {
        let csv = ExportService.csv(rows: [
            makeRow(label: "Has \"quotes\"")
        ])
        // RFC 4180: " becomes "" and the field is wrapped in quotes
        XCTAssertTrue(csv.contains("\"Has \"\"quotes\"\"\""))
    }

    func testCSVEscapesNewline() {
        let csv = ExportService.csv(rows: [
            makeRow(label: "Line one\nLine two")
        ])
        XCTAssertTrue(csv.contains("\"Line one\nLine two\""))
    }

    func testCSVNilFields() {
        let csv = ExportService.csv(rows: [makeRow()])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertTrue(lines[1].hasPrefix("10.0.0.1,,,,,,"))
    }

    func testCSVMultipleRows() {
        let csv = ExportService.csv(rows: [
            makeRow(ip: "10.0.0.1", openPorts: [80]),
            makeRow(ip: "10.0.0.2", openPorts: [22, 443])
        ])
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)  // header + 2 rows
        XCTAssertTrue(lines[1].contains("10.0.0.1"))
        XCTAssertTrue(lines[1].contains(",80"))
        XCTAssertTrue(lines[2].contains("10.0.0.2"))
        XCTAssertTrue(lines[2].contains("22;443"))
    }

    func testJSONRoundtrip() throws {
        let original = [
            makeRow(
                ip: "10.0.0.1",
                label: "Router",
                hostname: "hgw",
                mac: "AA:BB",
                vendor: "Test",
                rttMs: 2.5,
                openPorts: [80, 443]
            )
        ]
        let data = try ExportService.json(rows: original)
        let decoded = try JSONDecoder().decode([ExportService.Row].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].ip, "10.0.0.1")
        XCTAssertEqual(decoded[0].label, "Router")
        XCTAssertEqual(decoded[0].openPorts, [80, 443])
    }
}
