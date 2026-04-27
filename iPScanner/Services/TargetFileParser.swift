import Foundation

/// Parses a target list file (`.txt` / `.csv`) into a deduplicated set of IPv4 addresses.
/// Each non-blank, non-comment line may contain one or more comma-separated tokens of:
///   * single IP        — `192.168.1.10`
///   * CIDR             — `10.0.0.0/24`
///   * range            — `192.168.1.50-192.168.1.100`
/// Blank lines and lines starting with `#` are ignored. Hostnames are out of scope (v1.2.0).
enum TargetFileParser {
    struct Result {
        let targets: [String]
        let invalidLines: [InvalidLine]
        let parsedTokenCount: Int
    }

    struct InvalidLine: Equatable {
        let lineNumber: Int
        let content: String
    }

    enum ParseError: Error, LocalizedError {
        case unreadable(URL)
        case noTargets

        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                "Could not read \(url.lastPathComponent)."
            case .noTargets:
                "The file did not contain any valid IP, CIDR, or range entries."
            }
        }
    }

    static func parse(url: URL) throws -> Result {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            throw ParseError.unreadable(url)
        }
        return parse(text: text)
    }

    static func parse(text: String) -> Result {
        var seen = Set<UInt32>()
        var invalid: [InvalidLine] = []
        var parsedTokenCount = 0

        for (idx, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            // A line may legitimately contain multiple comma-separated tokens.
            let tokens = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for token in tokens where !token.isEmpty {
                if let ipInt = IPv4.uint32(from: token) {
                    seen.insert(ipInt)
                    parsedTokenCount += 1
                } else if let range = ScanRange.parse(token) {
                    if range.upperBound >= range.lowerBound {
                        for v in range.lowerBound...range.upperBound { seen.insert(v) }
                    }
                    parsedTokenCount += 1
                } else {
                    invalid.append(InvalidLine(lineNumber: idx + 1, content: token))
                }
            }
        }

        let targets = seen.sorted().map(IPv4.string(from:))
        return Result(targets: targets, invalidLines: invalid, parsedTokenCount: parsedTokenCount)
    }
}
