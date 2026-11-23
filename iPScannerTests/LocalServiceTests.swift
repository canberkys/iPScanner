import XCTest
import Network
@testable import iPScanner

private final class LocalTCPService: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "ipscanner.test.service")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    init(reply: Data?, waitForRequest: Bool = false) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.lock.lock(); self.connections.append(connection); self.lock.unlock()
            connection.stateUpdateHandler = { state in
                guard case .ready = state, let reply else { return }
                let send = { connection.send(content: reply, completion: .contentProcessed { _ in }) }
                if waitForRequest { connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in send() } }
                else { send() }
            }
            connection.start(queue: self.queue)
        }
    }
    func start() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(returning: Int(self.listener.port!.rawValue))
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }
    func stop() {
        listener.cancel()
        lock.lock(); let active = connections; connections.removeAll(); lock.unlock()
        active.forEach { $0.stateUpdateHandler = nil; $0.cancel() }
    }
}

final class LocalServiceTests: XCTestCase {
    func testHTTPTitleAndOpenPortFromControlledService() async throws {
        let body = "<html><title>Local &amp; controlled</title></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let service = try LocalTCPService(reply: Data(response.utf8), waitForRequest: true)
        defer { service.stop() }
        let port = try await service.start()
        let ports = await PortScanner.probe("127.0.0.1", ports: [port])
        XCTAssertEqual(ports, [port])
        let title = await BannerProbe.fetchHTTPTitle("127.0.0.1", port: port)
        XCTAssertEqual(title, "Local & controlled")
    }
    func testSSHBannerAndTimeout() async throws {
        let service = try LocalTCPService(reply: Data("SSH-2.0-iPScannerTest\r\n".utf8))
        defer { service.stop() }
        let port = try await service.start()
        let banner = await BannerProbe.fetchSSHBanner("127.0.0.1", port: port)
        XCTAssertTrue(banner?.contains("iPScannerTest") == true)
        let silent = try LocalTCPService(reply: nil)
        defer { silent.stop() }
        let silentPort = try await silent.start()
        let start = Date()
        let missing = await BannerProbe.fetchSSHBanner("127.0.0.1", port: silentPort, timeoutMs: 100)
        XCTAssertNil(missing)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
    func testActiveBannerCancellation() async throws {
        let service = try LocalTCPService(reply: nil)
        defer { service.stop() }
        let port = try await service.start()
        let task = Task { await BannerProbe.fetchSSHBanner("127.0.0.1", port: port, timeoutMs: 5000) }
        try await Task.sleep(for: .milliseconds(100))
        let start = Date(); task.cancel()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
    func testMagicPacketAndRejectedGroupAddress() {
        let packet = WakeOnLAN.magicPacket(mac: "28-6f-b9-00-00-01")!
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(packet.prefix(6), Data(repeating: 255, count: 6))
        for offset in stride(from: 6, to: 102, by: 6) {
            XCTAssertEqual(Array(packet[offset..<(offset+6)]), [0x28, 0x6f, 0xb9, 0, 0, 1])
        }
        XCTAssertNil(WakeOnLAN.magicPacket(mac: "ff:ff:ff:ff:ff:ff"))
        XCTAssertNil(WakeOnLAN.magicPacket(mac: "28:6f:b9:00:00:ZZ"))
    }

    func testBannerRedirectsStayOnProbedHost() {
        let origin = URL(string: "http://192.168.1.1/")
        XCTAssertTrue(BannerSessionDelegate.allowsRedirect(from: origin, to: URL(string: "https://192.168.1.1:8443/login")))
        XCTAssertFalse(BannerSessionDelegate.allowsRedirect(from: origin, to: URL(string: "https://cloud.example.com/")))
        XCTAssertFalse(BannerSessionDelegate.allowsRedirect(from: origin, to: URL(string: "http://192.168.1.2/")))
        XCTAssertFalse(BannerSessionDelegate.allowsRedirect(from: nil, to: origin))
    }
}
