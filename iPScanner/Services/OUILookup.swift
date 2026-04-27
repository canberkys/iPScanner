import Foundation

final class OUILookup: @unchecked Sendable {
    static let shared = OUILookup()

    private let mal: [String: String]   // 24-bit prefixes (6 hex chars)
    private let mam: [String: String]   // 28-bit prefixes (7 hex chars)
    private let mas: [String: String]   // 36-bit prefixes (9 hex chars)

    private init() {
        self.mas = Self.parseSubBlock(filename: "oui36", subPrefixHexLength: 3)
        self.mam = Self.parseSubBlock(filename: "oui28", subPrefixHexLength: 1)
        self.mal = Self.parseMAL(filename: "oui")
    }

    /// Test-only initializer that bypasses the bundled OUI files.
    init(mas: [String: String], mam: [String: String], mal: [String: String]) {
        self.mas = mas
        self.mam = mam
        self.mal = mal
    }

    /// Returns vendor name for a MAC address, or nil if not found in any IEEE registry.
    /// Most specific lookup wins (MA-S → MA-M → MA-L).
    func vendor(forMAC mac: String) -> String? {
        let normalized = Self.normalizedHex(mac)
        guard normalized.count >= 9 else { return mal[String(normalized.prefix(6))] }

        let masKey = String(normalized.prefix(9))
        if let v = mas[masKey] { return v }

        let mamKey = String(normalized.prefix(7))
        if let v = mam[mamKey] { return v }

        let malKey = String(normalized.prefix(6))
        return mal[malKey]
    }

    static func normalizedHex(_ mac: String) -> String {
        let segments = mac.split(separator: ":", omittingEmptySubsequences: false)
        guard segments.count >= 5 else { return "" }
        return segments.prefix(5).map { seg -> String in
            let s = String(seg).uppercased()
            return s.count == 1 ? "0\(s)" : s
        }.joined()
    }

    // MARK: - Parsers

    private static func parseMAL(filename: String) -> [String: String] {
        guard let content = loadFile(filename) else { return [:] }
        var dict: [String: String] = [:]
        dict.reserveCapacity(35_000)
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = line.firstMatch(
                of: #/^([0-9A-Fa-f]{2})-([0-9A-Fa-f]{2})-([0-9A-Fa-f]{2})\s+\(hex\)\s+(.+)$/#
            ) else { continue }
            let key = "\(match.1)\(match.2)\(match.3)".uppercased()
            let vendor = String(match.4).trimmingCharacters(in: .whitespacesAndNewlines)
            dict[key] = vendor
        }
        return dict
    }

    /// Parses MA-M (28-bit) or MA-S (36-bit) registries.
    /// Each assignment occupies two lines:
    ///   `XX-XX-XX   (hex)        Vendor`
    ///   `YYYYYY-ZZZZZZ   (base 16)        Vendor`
    /// The fixed sub-prefix is the first `subPrefixHexLength` chars of `YYYYYY`.
    private static func parseSubBlock(filename: String, subPrefixHexLength: Int) -> [String: String] {
        guard let content = loadFile(filename) else { return [:] }
        var dict: [String: String] = [:]
        dict.reserveCapacity(40_000)
        var lastOUI: String?

        for raw in content.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let m = line.firstMatch(
                of: #/^([0-9A-Fa-f]{2})-([0-9A-Fa-f]{2})-([0-9A-Fa-f]{2})\s+\(hex\)\s+/#
            ) {
                lastOUI = "\(m.1)\(m.2)\(m.3)".uppercased()
                continue
            }
            if let oui = lastOUI,
               let m = line.firstMatch(
                of: #/^([0-9A-Fa-f]{6})-[0-9A-Fa-f]{6}\s+\(base\s+16\)\s+(.+)$/#
               ) {
                let rangeStart = String(m.1).uppercased()
                let subPrefix = String(rangeStart.prefix(subPrefixHexLength))
                let key = oui + subPrefix
                let vendor = String(m.2).trimmingCharacters(in: .whitespacesAndNewlines)
                if !vendor.isEmpty {
                    dict[key] = vendor
                }
            }
        }
        return dict
    }

    private static func loadFile(_ name: String) -> String? {
        for url in candidateURLs(for: name) {
            if let data = try? Data(contentsOf: url) {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    /// Search paths the OUI files might live in. Ordered by likelihood.
    /// Lets the same loader work from inside the app bundle and from the
    /// `ipscanner` CLI binary that ships alongside it in `Contents/MacOS/`.
    private static func candidateURLs(for name: String) -> [URL] {
        var urls: [URL] = []
        // 1. Standard app-bundle resource lookup (works for the GUI app).
        if let url = Bundle.main.url(forResource: name, withExtension: "txt") {
            urls.append(url)
        }
        let fileName = "\(name).txt"
        // 2. Sibling of the executable: `Contents/MacOS/ipscanner` → `Contents/Resources/oui.txt`.
        let exeDir = Bundle.main.bundleURL
        let bundleResources = exeDir.deletingLastPathComponent().appendingPathComponent("Resources")
        urls.append(bundleResources.appendingPathComponent(fileName))
        // 3. Same directory as the binary (loose distribution).
        urls.append(exeDir.appendingPathComponent(fileName))
        // 4. Current working directory (developer convenience).
        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(fileName))
        return urls
    }
}
