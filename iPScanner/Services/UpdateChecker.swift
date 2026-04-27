import Foundation
import Observation

/// Polite check against the GitHub Releases API to see if a newer iPScanner
/// is published. Zero-dependency, no auto-install: when an update is found
/// we surface an alert with a "View Release" button that opens the release
/// page in the user's browser.
@Observable
@MainActor
final class UpdateChecker {
    struct AvailableUpdate: Equatable {
        let currentVersion: String
        let latestVersion: String
        let releaseURL: URL
        let releaseName: String
    }

    private(set) var availableUpdate: AvailableUpdate?
    private(set) var lastError: String?
    private(set) var isChecking: Bool = false

    static let releasesAPI = URL(string: "https://api.github.com/repos/canberkys/iPScanner/releases/latest")!
    static let autoCheckInterval: TimeInterval = 24 * 60 * 60  // 24 hours

    nonisolated static func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    /// Manual trigger: always hits the API.
    func checkForUpdates() async {
        await runCheck()
    }

    /// Auto-check helper. Skips the network round-trip if `lastCheckAt`
    /// is younger than `autoCheckInterval`.
    func autoCheckIfNeeded(lastCheckAt: Date?) async -> Date {
        let now = Date()
        if let last = lastCheckAt, now.timeIntervalSince(last) < Self.autoCheckInterval {
            return last
        }
        await runCheck()
        return now
    }

    func clearAvailableUpdate() {
        availableUpdate = nil
    }

    private func runCheck() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            let current = Self.currentVersion()
            if Self.isNewer(release.normalizedTag, than: current) {
                availableUpdate = AvailableUpdate(
                    currentVersion: current,
                    latestVersion: release.normalizedTag,
                    releaseURL: release.htmlURL,
                    releaseName: release.name ?? release.tagName
                )
            } else {
                availableUpdate = nil
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Version comparison

    /// Semver-ish comparison. Strips a leading `v`, splits on dots, compares
    /// numerically component-by-component. Trailing zeros count as equal
    /// (`1.2.0` == `1.2`).
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = parseVersion(candidate)
        let rhs = parseVersion(current)
        let length = max(lhs.count, rhs.count)
        for i in 0..<length {
            let a = i < lhs.count ? lhs[i] : 0
            let b = i < rhs.count ? rhs[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    nonisolated static func parseVersion(_ raw: String) -> [Int] {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        // Drop pre-release / build metadata after `-` or `+`
        if let cut = s.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            s = String(s[..<cut])
        }
        return s.split(separator: ".").compactMap { Int($0) }
    }

    // MARK: - GitHub API

    struct Release: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: URL

        var normalizedTag: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
        }
    }

    enum UpdateError: Error, LocalizedError {
        case invalidResponse
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "GitHub Releases API did not return a successful response."
            case .decodingFailed: "Could not decode the release payload."
            }
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: Self.releasesAPI)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("iPScanner-update-check", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(Release.self, from: data)
        } catch {
            throw UpdateError.decodingFailed
        }
    }
}
