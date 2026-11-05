import Foundation

/// Combines the hostname sources a scan can produce. Reverse DNS is often empty
/// on home networks, where devices announce themselves over mDNS or NetBIOS
/// instead, so the Hostname column falls back through those.
enum HostNames {
    static func preferred(dns: String?, mdns: String?, netbios: String?) -> String? {
        for candidate in [dns, mdns, netbios] {
            if let value = candidate?.trimmingCharacters(in: .whitespaces), !value.isEmpty { return value }
        }
        return nil
    }

    /// The OUI database can lag behind newly registered prefixes, leaving the vendor
    /// blank for current hardware. Fall back to what the device itself reveals.
    static func vendor(registered: String?, names: [String?], serviceTypes: [String]) -> String? {
        if let v = registered, !v.isEmpty { return v }
        if serviceTypes.contains("_companion-link._tcp") { return "Apple, Inc." }
        let appleHints = ["macbook", "mac-mini", "mac-studio", "mac-pro", "imac", "iphone", "ipad", "apple-tv", "appletv"]
        for name in names.compactMap({ $0?.lowercased() }) {
            if appleHints.contains(where: name.contains) { return "Apple, Inc." }
            // macOS's default NetBIOS name: MAC-XXXXXX
            if name.range(of: "^mac-[0-9a-f]{6}$", options: .regularExpression) != nil { return "Apple, Inc." }
        }
        return nil
    }
}
