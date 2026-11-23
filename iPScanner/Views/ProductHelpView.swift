import SwiftUI

struct ProductHelpView: View {
    @State private var selection = "Getting Started"
    private let topics: [(String, String, String)] = [
        ("Getting Started", "play.circle", "Choose your network from the globe menu, keep Standard selected in Options, then press Scan. Results appear as devices respond.\n\nYou can enter a single IP (192.168.1.10), a subnet (192.168.1.0/24), or a range (192.168.1.10-192.168.1.50). Tools → Import Targets accepts text or CSV files. An imported file replaces the target field until you remove it.\n\nScan networks you own or have permission to inspect."),
        ("Scan Profiles", "slider.horizontal.3", "Quick uses ping and is best for a fast check. Devices that block ping may be missed.\n\nStandard adds TCP discovery and is the recommended starting point.\n\nDeep also scans ports and reads service banners. It takes longer. Stop ends the active scan, including ports and banners.\n\nAutomatic rescan in Options waits until every stage finishes before starting its countdown."),
        ("Results & Details", "tablecells", "Search by address, hostname, vendor, label or tag. Use Filters to narrow the list and Columns to choose visible information.\n\nSelect a device and click the details button, or press ⌘⌥I. Details open beside the table in wide windows and in a sheet in compact windows.\n\nRight-click a device for connection, copy and diagnostic actions. An open port identifies a reachable service; it is not a security assessment."),
        ("Save & Compare", "doc.on.doc", "File → Save Scan stores a snapshot you can reopen later. File → Compare to Scan compares the current results with a saved snapshot.\n\nUse Export above the results for CSV, JSON, text reports or IP:Port lists. Review exported network information before sharing it.\n\nThe star beside the target saves a range. Show the sidebar to return to saved networks."),
        ("Troubleshooting", "wrench.and.screwdriver", "No devices found? Check that the selected subnet matches your active Wi-Fi or Ethernet network. A VPN may change the route. Try Standard if Quick returns nothing.\n\nSome devices block discovery probes; no response does not prove a device is offline. Names and MAC addresses may be unavailable across routed networks. macOS 27 can additionally restrict MAC access to signed apps with the Network Topology Observation capability; local network permission alone may not be enough. Locally administered MAC addresses do not identify a manufacturer. Device types are estimates; their evidence appears in device details.\n\nIf macOS requests local network access, allow it to scan your network. Review any scan warnings for more detail.\n\nFor a repeatable problem, use Help → Report an Issue… and describe the steps and expected result."),
        ("Keyboard Shortcuts", "keyboard", "⌘R — Scan again\n⌘. — Stop\n⌘O — Open a saved scan\n⌘⌥S — Save a scan\n⌘S — Export CSV\n⌘⇧S — Export JSON\n⌘⌥I — Toggle device details\n⌘, — Settings"),
        ("Updates & Privacy", "arrow.down.circle", "Sparkle can check the GitHub update feed daily while iPScanner is running. Enable or disable checks in Settings. Manual checks remain available in Help and Settings.\n\nWhen an update is available, review its release notes and choose Download and Install. Updates are signed and verified before extraction; installation remains under your control.\n\nThere is no telemetry. Send Feedback sends the previewed text and optional environment information through Cloudflare to create a PUBLIC GitHub issue. No GitHub account is required. Scan results, IP addresses and MAC addresses are not attached automatically."),
        ("What's New", "sparkles", "Version 1.3.2\n\n• Devices that block ping but refuse a connection are now found.\n• Port scans keep earlier results; refreshing keeps a device's MAC address and label.\n• Opening a scan file asks before keeping its labels.\n• Wake-on-LAN also reaches each local Ethernet and Wi-Fi subnet.\n• Menu commands act on the front window only; New Window (⌘N) is back.\n• Safer address parsing, CSV exports and local web title checks.")
    ]
    var body: some View {
        HStack(spacing: 0) {
            List(topics, id: \.0, selection: $selection) { topic in
                Label(topic.0, systemImage: topic.1).tag(topic.0)
            }.frame(width: 205)
            Divider()
            ScrollView {
                if let topic = topics.first(where: { $0.0 == selection }) {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(topic.0, systemImage: topic.1).font(.title2.bold())
                        Text(topic.2).textSelection(.enabled).lineSpacing(5)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
                }
            }
        }.frame(minWidth: 720, minHeight: 460)
    }
}
