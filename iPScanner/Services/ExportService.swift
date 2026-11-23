import Foundation

enum ExportService {
    struct Row: Codable {
        let ip: String
        let label: String?
        let hostname: String?
        let mac: String?
        let vendor: String?
        let rttMs: Double?
        let ttl: Int?
        let openPorts: [Int]
        let netbiosName: String?
        let workgroup: String?
        let serviceTitle: String?
        var vendorStatus: VendorStatus? = nil
        let status: Host.Status
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
                ttl: h.ttl,
                openPorts: h.openPorts,
                netbiosName: h.netbiosName,
                workgroup: h.workgroup,
                serviceTitle: h.serviceTitle,
                vendorStatus: h.vendorStatus,
                status: h.status
            )
        }
    }

    static func csv(rows: [Row]) -> String {
        var out = "IP,Label,Hostname,MAC,Vendor,RTT (ms),TTL,Open Ports,NetBIOS Name,Workgroup,Service Title,Status\n"
        for r in rows {
            let rtt = r.rttMs.map { String(format: "%.1f", $0) } ?? ""
            let ttl = r.ttl.map(String.init) ?? ""
            let ports = r.openPorts.map(String.init).joined(separator: ";")
            let cells = [
                escape(r.ip),
                escape(r.label),
                escape(r.hostname),
                escape(r.mac),
                escape(r.vendor),
                rtt,
                ttl,
                escape(ports),
                escape(r.netbiosName),
                escape(r.workgroup),
                escape(r.serviceTitle),
                escape(statusLabel(r.status))
            ]
            out += cells.joined(separator: ",") + "\n"
        }
        return out
    }

    private static func statusLabel(_ status: Host.Status) -> String {
        switch status {
        case .alive: return "alive"
        case .dead: return "dead"
        case .scanning: return "scanning"
        }
    }

    static func json(rows: [Row]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(rows)
    }

    /// Flat `ip:port` lines, one per (host, open port) pair. Skips hosts with no open ports.
    /// Convenient for piping into Nmap, firewall rule generators, or `xargs`.
    static func ipPortList(rows: [Row]) -> String {
        var lines: [String] = []
        for r in rows where !r.openPorts.isEmpty {
            for port in r.openPorts {
                lines.append("\(r.ip):\(port)")
            }
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    /// Human-readable plain-text report. Suitable for tickets, email, Slack snippets.
    static func textReport(rows: [Row], rangeInput: String, scannedTotal: Int, aliveCount: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var out = "iPScanner Report\n"
        out += "Generated: \(formatter.string(from: Date()))\n"
        if !rangeInput.isEmpty { out += "Range: \(rangeInput)\n" }
        out += "Scanned: \(scannedTotal)\n"
        out += "Alive: \(aliveCount)\n"
        out += String(repeating: "-", count: 60) + "\n"

        // Column widths derived from data so output stays aligned without truncating.
        // Hostname falls back to the NetBIOS computer name when DNS didn't resolve one.
        let ipWidth      = max(15, rows.map { $0.ip.count }.max() ?? 15)
        let hostWidth    = max(20, rows.map { ($0.hostname ?? $0.netbiosName ?? "").count }.max() ?? 20)
        let vendorWidth  = max(20, rows.map { ($0.vendor ?? "").count }.max() ?? 20)
        let statusWidth  = max(8, rows.map { statusLabel($0.status).count }.max() ?? 8)

        out += pad("IP", to: ipWidth) + "  "
            + pad("Hostname", to: hostWidth) + "  "
            + pad("Vendor", to: vendorWidth) + "  "
            + pad("Status", to: statusWidth) + "  "
            + "Ports\n"
        out += String(repeating: "-", count: 60) + "\n"
        for r in rows {
            let ports = r.openPorts.map(String.init).joined(separator: ", ")
            let title = r.serviceTitle.map { " · \($0)" } ?? ""
            out += pad(r.ip, to: ipWidth) + "  "
                + pad(r.hostname ?? r.netbiosName ?? "—", to: hostWidth) + "  "
                + pad(r.vendor ?? "—", to: vendorWidth) + "  "
                + pad(statusLabel(r.status), to: statusWidth) + "  "
                + (ports.isEmpty ? "—" : ports) + title + "\n"
        }
        return out
    }

    static func defaultFileName(ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "iPScanner-\(formatter.string(from: Date())).\(ext)"
    }

    /// Characters that make spreadsheet apps evaluate a cell as a formula.
    private static let formulaTriggers: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    static func escape(_ value: String?) -> String {
        guard var v = value, !v.isEmpty else { return "" }
        // Values such as HTTP titles come from untrusted devices; prefix a quote so
        // `=HYPERLINK(...)` is shown as text instead of being run as a formula.
        if let first = v.first, formulaTriggers.contains(first) { v = "'" + v }
        if v.contains(",") || v.contains("\"") || v.contains("\n") || v.contains("\r") {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }

    private static func pad(_ s: String, to width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }
}
