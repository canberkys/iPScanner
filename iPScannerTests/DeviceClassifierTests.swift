import XCTest
@testable import iPScanner

final class DeviceClassifierTests: XCTestCase {

    private func host(
        ip: String = "10.0.0.1",
        hostname: String? = nil,
        mac: String? = nil,
        vendor: String? = nil,
        openPorts: [Int] = [],
        serviceTitle: String? = nil
    ) -> iPScanner.Host {
        iPScanner.Host(
            ip: ip,
            hostname: hostname,
            mac: mac,
            vendor: vendor,
            openPorts: openPorts,
            serviceTitle: serviceTitle,
            status: .alive
        )
    }

    // MARK: - Routers

    func testRouterByVendor() {
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "HUAWEI TECHNOLOGIES CO.,LTD")), .router)
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "TP-LINK TECHNOLOGIES CO.,LTD.")), .router)
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "NETGEAR")), .router)
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "ASUSTeK COMPUTER INC.")), .router)
    }

    func testRouterByHostname() {
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "hgw.local")), .router)
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "gateway.lan")), .router)
    }

    // MARK: - Printer

    func testPrinterByPort9100() {
        XCTAssertEqual(DeviceClassifier.classify(host(openPorts: [9100])), .printer)
    }

    func testPrinterByPort631IPP() {
        XCTAssertEqual(DeviceClassifier.classify(host(openPorts: [631])), .printer)
    }

    func testPrinterByVendor() {
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "Hewlett Packard")), .printer)
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "Brother Industries")), .printer)
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "Canon Inc.")), .printer)
    }

    // MARK: - TV

    func testVestelTV() {
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "Vestel Elektronik San ve Tic. A.S.")), .tv)
    }

    func testTVByHostname() {
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "livingroom-tv.local")), .tv)
    }

    // MARK: - NAS

    func testSynologyNAS() {
        XCTAssertEqual(DeviceClassifier.classify(host(vendor: "Synology Incorporated", openPorts: [5000])), .nas)
    }

    func testNASByPort() {
        XCTAssertEqual(DeviceClassifier.classify(host(openPorts: [5000])), .nas)
    }

    // MARK: - Phone

    func testIPhoneByHostname() {
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "iphone.local", vendor: "Apple, Inc.")), .phone)
    }

    func testIPad() {
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "ipad.local", vendor: "Apple, Inc.")), .phone)
    }

    // MARK: - Mac

    func testMacByVendor() {
        XCTAssertEqual(DeviceClassifier.classify(host(hostname: "macbook.local", vendor: "Apple, Inc.")), .mac)
    }

    // MARK: - Unknown

    func testEmptyHost() {
        XCTAssertEqual(DeviceClassifier.classify(host()), .unknown)
    }

    func testRandomMACWithNothing() {
        // Locally-administered MAC, no other signals.
        XCTAssertEqual(DeviceClassifier.classify(host(mac: "AA:BB:CC:DD:EE:FF")), .unknown)
    }

    // MARK: - Symbols

    func testAllDeviceTypesHaveSymbols() {
        for type in [DeviceType.router, .printer, .tv, .mac, .phone, .server, .nas, .iot, .windows, .unknown] {
            XCTAssertFalse(type.sfSymbol.isEmpty, "\(type) missing SF Symbol")
            XCTAssertFalse(type.label.isEmpty, "\(type) missing label")
        }
    }
}
