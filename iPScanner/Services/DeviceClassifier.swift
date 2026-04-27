import Foundation

enum DeviceType: String, Hashable {
    case router
    case printer
    case tv
    case mac
    case phone
    case server
    case nas
    case iot
    case windows
    case unknown

    var sfSymbol: String {
        switch self {
        case .router: "wifi.router"
        case .printer: "printer"
        case .tv: "tv"
        case .mac: "laptopcomputer"
        case .phone: "iphone"
        case .server: "server.rack"
        case .nas: "externaldrive.connected.to.line.below"
        case .iot: "homekit"
        case .windows: "pc"
        case .unknown: "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .router: "Router"
        case .printer: "Printer"
        case .tv: "TV"
        case .mac: "Mac"
        case .phone: "Phone"
        case .server: "Server"
        case .nas: "NAS"
        case .iot: "IoT"
        case .windows: "Windows"
        case .unknown: "—"
        }
    }
}

enum DeviceClassifier {
    /// Best-effort guess from MAC vendor, open ports, hostname, and service title.
    static func classify(_ host: Host) -> DeviceType {
        let vendor = (host.vendor ?? "").lowercased()
        let hostname = (host.hostname ?? "").lowercased()
        let title = (host.serviceTitle ?? "").lowercased()
        let ports = Set(host.openPorts)

        // Printers — port 9100 (RAW), 631 (IPP), 515 (LPD), or "printer" hint
        if ports.contains(9100) || ports.contains(631) || ports.contains(515)
            || vendor.contains("hewlett") || vendor.contains("brother")
            || vendor.contains("canon") || vendor.contains("epson")
            || vendor.contains("lexmark") || vendor.contains("xerox")
            || hostname.contains("printer") || title.contains("laserjet")
            || title.contains("officejet") || title.contains("brother") {
            return .printer
        }

        // TVs — Vestel, LG, Samsung TV, AirPlay receiver
        if vendor.contains("vestel") || vendor.contains("lg electronics")
            || vendor.contains("samsung") && hostname.contains("tv")
            || hostname.contains("tv") || title.contains("smart tv") {
            return .tv
        }

        // Routers — common router vendors, hostname hgw.local, port 53/5353/443 web admin
        if vendor.contains("huawei") || vendor.contains("zte")
            || vendor.contains("tp-link") || vendor.contains("netgear")
            || vendor.contains("asustek") || vendor.contains("ubiquiti")
            || vendor.contains("mikrotik") || vendor.contains("cisco")
            || hostname.contains("hgw") || hostname.contains("router")
            || hostname.contains("gateway") || title.contains("login")
            || title.contains("router") {
            return .router
        }

        // NAS — Synology, QNAP, port 5000/5001/548 (AFP)/2049 (NFS)
        if vendor.contains("synology") || vendor.contains("qnap")
            || hostname.contains("nas") || ports.contains(5000)
            || ports.contains(5001) || ports.contains(548)
            || ports.contains(2049) {
            return .nas
        }

        // Phones — Apple iPhone (random MAC often), hostname iphone/ipad, common pattern
        if hostname.contains("iphone") || hostname.contains("ipad")
            || hostname.contains("android") {
            return .phone
        }

        // Macs — Apple vendor + non-phone
        if vendor.contains("apple") && !hostname.contains("iphone") && !hostname.contains("ipad") {
            return .mac
        }

        // Windows — port 445 + common Windows hint
        if ports.contains(445) && (ports.contains(135) || ports.contains(139)
            || hostname.contains("desktop") || hostname.contains("laptop")
            || hostname.contains("pc")) {
            return .windows
        }

        // Server — SSH or web service open + no other hint
        if ports.contains(22) || ports.contains(80) || ports.contains(443) || ports.contains(8080) {
            return .server
        }

        // IoT — small port set, Espressif/Tuya/Sonoff vendors
        if vendor.contains("espressif") || vendor.contains("tuya")
            || vendor.contains("sonoff") || vendor.contains("xiaomi")
            || vendor.contains("nest") || vendor.contains("philips") {
            return .iot
        }

        return .unknown
    }
}
