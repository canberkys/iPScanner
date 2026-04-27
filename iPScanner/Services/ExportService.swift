import Foundation

enum ExportService {
    struct Row: Codable {
        let ip: String
        let label: String?
        let hostname: String?
        let mac: String?
        let vendor: String?
        let rttMs: Double?
        let openPorts: [Int]
    }

    static func rows(from hosts: [Host], label: (Host) -> String?) -> [Row] {
        hosts.map { h in
            Row(
                ip: h.ip,
                label: label(h),
                hostname: h.hostname,
                mac: h.mac,
                vendor: h.vendor,
                rttMs: h.rttMs,
                openPorts: h.openPorts
            )
        }
    }

    static func csv(rows: [Row]) -> String {
        var out = "IP,Label,Hostname,MAC,Vendor,RTT (ms),Open Ports\n"
        for r in rows {
            let rtt = r.rttMs.map { String(format: "%.1f", $0) } ?? ""
            let ports = r.openPorts.map(String.init).joined(separator: ";")
            let cells = [
                escape(r.ip),
                escape(r.label),
                escape(r.hostname),
                escape(r.mac),
                escape(r.vendor),
                rtt,
                escape(ports)
            ]
            out += cells.joined(separator: ",") + "\n"
        }
        return out
    }

    static func json(rows: [Row]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(rows)
    }

    static func defaultFileName(ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "iPScanner-\(formatter.string(from: Date())).\(ext)"
    }

    private static func escape(_ value: String?) -> String {
        guard let v = value, !v.isEmpty else { return "" }
        if v.contains(",") || v.contains("\"") || v.contains("\n") || v.contains("\r") {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }
}
