import Foundation

enum RescanInterval: String, CaseIterable, Identifiable, Sendable {
    case off
    case s30
    case m1
    case m5
    case m15

    var id: String { rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .off: nil
        case .s30: 30
        case .m1: 60
        case .m5: 300
        case .m15: 900
        }
    }

    var label: String {
        switch self {
        case .off: "Off"
        case .s30: "30s"
        case .m1: "1m"
        case .m5: "5m"
        case .m15: "15m"
        }
    }

    var menuLabel: String {
        switch self {
        case .off: "Auto-rescan: off"
        case .s30: "Auto-rescan every 30s"
        case .m1: "Auto-rescan every 1m"
        case .m5: "Auto-rescan every 5m"
        case .m15: "Auto-rescan every 15m"
        }
    }
}
