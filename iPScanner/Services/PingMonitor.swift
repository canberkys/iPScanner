import Foundation
import Observation

@Observable
@MainActor
final class PingMonitor {
    static let bufferSize = 60

    private(set) var samples: [Double?] = []
    private(set) var trackedIP: String?
    private var task: Task<Void, Never>?

    var lastRTT: Double? { samples.last.flatMap { $0 } }

    var avgRTT: Double? {
        let alive = samples.compactMap { $0 }
        guard !alive.isEmpty else { return nil }
        return alive.reduce(0, +) / Double(alive.count)
    }

    var minRTT: Double? { samples.compactMap { $0 }.min() }
    var maxRTT: Double? { samples.compactMap { $0 }.max() }

    var lossRate: Double {
        guard !samples.isEmpty else { return 0 }
        let lost = samples.filter { $0 == nil }.count
        return Double(lost) / Double(samples.count)
    }

    func start(ip: String) {
        if trackedIP == ip { return }
        stop()
        trackedIP = ip
        samples = []

        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let ip = self?.trackedIP else { break }
                let rtt = await NetworkScanner.ping(ip)
                if Task.isCancelled { break }
                guard let self, self.trackedIP == ip else { break }
                self.samples.append(rtt)
                if self.samples.count > Self.bufferSize {
                    self.samples.removeFirst(self.samples.count - Self.bufferSize)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        trackedIP = nil
        samples = []
    }
}
