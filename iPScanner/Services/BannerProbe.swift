import Foundation
import Network

enum BannerProbe {
    /// Returns a short banner/title for a host based on what's responding on standard ports.
    /// Priority: HTTPS title (443) > HTTP title (80) > SSH banner (22).
    static func fetch(_ ip: String, openPorts: [Int]) async -> String? {
        if openPorts.contains(443) {
            if let t = await fetchHTTPTitle(ip, scheme: "https") { return t }
        }
        if openPorts.contains(80) {
            if let t = await fetchHTTPTitle(ip, scheme: "http") { return t }
        }
        if openPorts.contains(22) {
            if let b = await fetchSSHBanner(ip) { return b }
        }
        return nil
    }

    // MARK: - HTTP title

    static func fetchHTTPTitle(
        _ ip: String,
        scheme: String = "http",
        timeout: TimeInterval = 1.5
    ) async -> String? {
        guard let url = URL(string: "\(scheme)://\(ip)/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("text/html,*/*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("iPScanner/1.0", forHTTPHeaderField: "User-Agent")

        let session = httpSession
        do {
            let (data, _) = try await session.data(for: request)
            let body = String(data: data.prefix(64 * 1024), encoding: .utf8) ?? ""
            return extractTitle(from: body)
        } catch {
            return nil
        }
    }

    private static let httpSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2.0
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // Trust self-signed certs on local devices via delegate
        return URLSession(configuration: config, delegate: TrustAllDelegate.shared, delegateQueue: nil)
    }()

    private static func extractTitle(from html: String) -> String? {
        guard let match = html.firstMatch(of: #/<title[^>]*>([\s\S]*?)<\/title>/#.ignoresCase()) else {
            return nil
        }
        let raw = String(match.1)
        let trimmed = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - SSH banner

    static func fetchSSHBanner(
        _ ip: String,
        port: Int = 22,
        timeoutMs: Int = 1000
    ) async -> String? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        let connection = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(ip), port: nwPort),
            using: .tcp
        )
        let queue = DispatchQueue.global(qos: .userInitiated)

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let state = ReadState(connection: connection, continuation: continuation)

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { data, _, _, _ in
                        guard let data, !data.isEmpty,
                              let line = String(data: data, encoding: .utf8) else {
                            state.finish(nil)
                            return
                        }
                        let firstLine = line
                            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                            .first
                            .map(String.init)
                        state.finish(firstLine?.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                case .failed, .cancelled:
                    state.finish(nil)
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
                state.finish(nil)
            }

            connection.start(queue: queue)
        }
    }

    private final class ReadState: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let connection: NWConnection
        private let continuation: CheckedContinuation<String?, Never>

        init(connection: NWConnection, continuation: CheckedContinuation<String?, Never>) {
            self.connection = connection
            self.continuation = continuation
        }

        func finish(_ value: String?) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            connection.cancel()
            continuation.resume(returning: value)
        }
    }
}

// Trust self-signed certs only for hosts in private/local IP ranges (RFC1918 + loopback + link-local).
// Public hosts use default validation so we don't accidentally MITM real internet services.
private final class TrustAllDelegate: NSObject, URLSessionDelegate {
    static let shared = TrustAllDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           Self.isLocalIP(host),
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// Returns true for RFC1918 private ranges, loopback, and link-local IPv4.
    private static func isLocalIP(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4,
              let a = UInt8(parts[0]),
              let b = UInt8(parts[1]) else { return false }
        if a == 10 { return true }                          // 10.0.0.0/8
        if a == 172, (16...31).contains(b) { return true }  // 172.16.0.0/12
        if a == 192, b == 168 { return true }               // 192.168.0.0/16
        if a == 169, b == 254 { return true }               // 169.254.0.0/16 link-local
        if a == 127 { return true }                         // 127.0.0.0/8 loopback
        return false
    }
}
