import Foundation
import Network

enum WakeOnLAN {
    enum WoLError: Error { case invalidMAC, sendFailed(Error) }

    static func wake(
        mac: String,
        broadcast: String = "255.255.255.255",
        port: UInt16 = 9
    ) async throws {
        guard let bytes = parseMAC(mac) else { throw WoLError.invalidMAC }

        let payload: Data = {
            var p = Data(repeating: 0xFF, count: 6)
            for _ in 0..<16 { p.append(contentsOf: bytes) }
            return p
        }()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw WoLError.invalidMAC }

        let params: NWParameters = .udp
        if let opts = params.defaultProtocolStack.transportProtocol as? NWProtocolUDP.Options {
            _ = opts
        }
        // Allow broadcast on the underlying socket.
        params.allowLocalEndpointReuse = true
        if let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(broadcast),
            port: nwPort,
            using: params
        )
        let queue = DispatchQueue.global(qos: .userInitiated)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let state = SendState()

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            state.finish(.failure(WoLError.sendFailed(error)),
                                         continuation: continuation,
                                         connection: connection)
                        } else {
                            state.finish(.success(()),
                                         continuation: continuation,
                                         connection: connection)
                        }
                    })
                case .failed(let error):
                    state.finish(.failure(WoLError.sendFailed(error)),
                                 continuation: continuation,
                                 connection: connection)
                case .cancelled:
                    state.finish(.success(()),
                                 continuation: continuation,
                                 connection: connection)
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + 1.5) {
                state.finish(.success(()),
                             continuation: continuation,
                             connection: connection)
            }

            connection.start(queue: queue)
        }
    }

    /// Wakes multiple MACs concurrently, ignoring per-host failures.
    static func wakeAll(macs: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for mac in macs {
                group.addTask { try? await Self.wake(mac: mac) }
            }
        }
    }

    private static func parseMAC(_ raw: String) -> [UInt8]? {
        let cleaned = raw
            .replacingOccurrences(of: "-", with: ":")
            .split(separator: ":")
        guard cleaned.count == 6 else { return nil }
        var bytes: [UInt8] = []
        for segment in cleaned {
            guard let v = UInt8(segment, radix: 16) else { return nil }
            bytes.append(v)
        }
        return bytes
    }

    private final class SendState: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func finish(
            _ result: Result<Void, Error>,
            continuation: CheckedContinuation<Void, Error>,
            connection: NWConnection
        ) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            connection.cancel()
            continuation.resume(with: result)
        }
    }
}
