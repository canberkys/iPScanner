import Foundation

enum ScanProfile: String, CaseIterable, Identifiable, Sendable {
    case quick
    case standard
    case deep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: "Quick"
        case .standard: "Standard"
        case .deep: "Deep"
        }
    }

    var description: String {
        switch self {
        case .quick:
            "ICMP ping only — fastest, misses ICMP-blocked hosts (e.g. Windows Firewall)."
        case .standard:
            "Ping + TCP fallback — finds hosts that block ICMP."
        case .deep:
            "Standard + auto port scan with banner fetch on alive hosts."
        }
    }

    var useTCPFallback: Bool {
        self != .quick
    }

    var autoPortScan: Bool {
        self == .deep
    }

    /// Standard / Deep run an extra UDP-137 query to pull NetBIOS computer name and workgroup.
    /// Quick skips it to keep ICMP-only discovery fast.
    var includeNetBIOS: Bool {
        self != .quick
    }
}
