import Foundation

struct ScanRange: Hashable {
    let displayString: String
    let lowerBound: UInt32
    let upperBound: UInt32

    var addresses: [String] {
        guard upperBound >= lowerBound else { return [] }
        return (lowerBound...upperBound).map(IPv4.string(from:))
    }

    var hostCount: Int { Int(upperBound) - Int(lowerBound) + 1 }

    static func parse(_ input: String) -> ScanRange? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if let r = ScanRange(cidr: trimmed) { return r }
        if let r = ScanRange(range: trimmed) { return r }
        if let r = ScanRange(singleIP: trimmed) { return r }
        return nil
    }

    init?(singleIP: String) {
        guard let value = IPv4.uint32(from: singleIP) else { return nil }
        self.lowerBound = value
        self.upperBound = value
        self.displayString = singleIP
    }

    /// Parses comma-separated input into multiple ranges.
    /// Returns the parsed list and the index (1-based) of the first invalid chunk, if any.
    static func parseAll(_ input: String) -> (ranges: [ScanRange], firstInvalidIndex: Int?) {
        let chunks = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var ranges: [ScanRange] = []
        for (idx, chunk) in chunks.enumerated() where !chunk.isEmpty {
            guard let r = parse(chunk) else {
                return (ranges, idx + 1)
            }
            ranges.append(r)
        }
        return (ranges, nil)
    }

    /// Total host count across ranges, computed WITHOUT expanding any address list.
    /// Callers must check this against their target-count limit before calling
    /// `uniqueAddresses`, which does expand every address into memory.
    static func totalHostCount(_ ranges: [ScanRange]) -> Int {
        ranges.reduce(0) { partial, r in
            let count = r.upperBound >= r.lowerBound ? r.hostCount : 0
            let (sum, overflow) = partial.addingReportingOverflow(count)
            return overflow ? Int.max : sum
        }
    }

    /// Combined unique addresses from multiple ranges, sorted numerically.
    static func uniqueAddresses(_ ranges: [ScanRange]) -> [String] {
        var seen = Set<UInt32>()
        seen.reserveCapacity(ranges.reduce(0) { $0 + $1.hostCount })
        for r in ranges where r.upperBound >= r.lowerBound {
            for v in r.lowerBound...r.upperBound { seen.insert(v) }
        }
        return seen.sorted().map(IPv4.string(from:))
    }

    init?(cidr: String) {
        guard let slash = cidr.firstIndex(of: "/") else { return nil }
        let ipPart = String(cidr[..<slash])
        let prefixPart = String(cidr[cidr.index(after: slash)...])
        guard let prefix = Int(prefixPart), (0...32).contains(prefix) else { return nil }
        guard let ipInt = IPv4.uint32(from: ipPart) else { return nil }

        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
        let network = ipInt & mask
        let broadcast = network | ~mask

        if prefix < 31 {
            self.lowerBound = network &+ 1
            self.upperBound = broadcast == 0 ? 0 : broadcast &- 1
        } else {
            self.lowerBound = network
            self.upperBound = broadcast
        }
        self.displayString = cidr
    }

    init?(range: String) {
        let parts = range.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lo = IPv4.uint32(from: parts[0]),
              let hi = IPv4.uint32(from: parts[1]),
              lo <= hi else { return nil }
        self.lowerBound = lo
        self.upperBound = hi
        self.displayString = range
    }
}

enum IPv4 {
    /// Parses canonical dotted-decimal IPv4 only: exactly four parts, ASCII digits,
    /// no signs, no empty parts and no leading zeros. Values like `010.0.0.1` are
    /// rejected because browsers, ssh and ping may read them as octal and reach a
    /// different host than the one displayed.
    static func uint32(from ip: String) -> UInt32? {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let octet = canonicalOctet(part) else { return nil }
            result = (result << 8) | UInt32(octet)
        }
        return result
    }

    private static func canonicalOctet(_ part: Substring) -> UInt8? {
        let bytes = part.utf8
        guard (1...3).contains(bytes.count),
              bytes.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else { return nil }
        if bytes.count > 1 && bytes.first == UInt8(ascii: "0") { return nil }
        return UInt8(part)
    }

    /// Collapses addresses into the range syntax `ScanRange.parseAll` accepts,
    /// e.g. ["10.0.0.1", "10.0.0.2", "10.0.0.9"] → "10.0.0.1-10.0.0.2, 10.0.0.9".
    static func collapsedRangeInput(_ addresses: [String]) -> String {
        let values = Set(addresses.compactMap(uint32(from:))).sorted()
        guard var start = values.first else { return "" }
        var end = start
        var chunks: [String] = []
        func flush() { chunks.append(start == end ? string(from: start) : "\(string(from: start))-\(string(from: end))") }
        for value in values.dropFirst() {
            if value == end &+ 1 { end = value } else { flush(); start = value; end = value }
        }
        flush()
        return chunks.joined(separator: ", ")
    }

    static func string(from value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }
}
