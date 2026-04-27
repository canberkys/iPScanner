<div align="center">
  <img src="assets/icon-with-text.png" width="220" alt="iPScanner">
  <h3><em>See every device on your network.</em></h3>
</div>

---

# iPScanner — A native macOS network scanner

Open-source macOS counterpart to Advanced IP Scanner. Built with native SwiftUI, zero third-party dependencies, universal binary (Apple Silicon + Intel).

---

## Features

### Discovery

- **CIDR + range input**: `10.0.0.0/24`, `192.168.1.50-192.168.1.200`, or comma-separated multiple ranges (`10.0.0.0/24, 172.16.0.0/24`)
- **Auto-detected default subnet** from the active interface (en0/en1)
- **Concurrent ping** (32 parallel) using `/sbin/ping`
- **TCP fallback probe** (445/80/443/22/3389) for hosts that block ICMP — Windows Firewall, etc.
- **Reverse DNS** with 1-second timeout (race-cancelable)
- **MAC address** via `arp -an` parsing
- **Vendor lookup** with the bundled IEEE OUI registry — MA-L (24-bit), MA-M (28-bit), and MA-S (36-bit) for sub-block accuracy
- **mDNS / Bonjour** service discovery (`_airplay`, `_homekit`, `_smb`, `_ssh`, `_ipp`, `_googlecast`, …)
- **HTTP / HTTPS title** and **SSH banner** fetch on demand (port-scan banner enrichment)

### Actions

- **Port scanner** — common-ports preset, web preset, custom ranges (`8000-8100`), bounded concurrency to avoid connection storms
- **Right-click context menu** per host: HTTP / HTTPS / SSH / VNC / RDP / SMB / AFP / Telnet / Ping in Terminal / Refresh / Wake-on-LAN / Show Details / Copy IP/Hostname/MAC / Remove from list
- **Wake-on-LAN** — UDP magic packet, single host or bulk
- **⌘C** copies selected IP(s) from the table
- **Multi-select** for bulk actions

### Inspector

Selecting a single host opens the right-side panel automatically — it shows:

- Header — device-type icon, IP, vendor, classification
- Inline label editor with `#tag` syntax (searchable, MAC-anchored, persisted)
- Full info: hostname, MAC, anchor, open ports (with service names), service title, RTT
- mDNS services list
- Live ping monitor — sparkline + avg / min / max / loss stats (1s interval, 60-sample buffer)
- Action grid grouped into Connect / Tools / Copy

### Persistence & I/O

- **Saved ranges** with friendly names (`Home`, `Office VLAN`) — sidebar with rename support
- **Snapshot save/load** — `.ipscan.json`, ⌘O / ⌘⌥S
- **Export** as CSV / JSON / clipboard
- Per-host labels persisted in `UserDefaults`

### UX

- macOS-native: NavigationSplitView (sidebar + detail + inspector), `ContentUnavailableView`, App-menu commands, custom About panel, GitHub Help menu
- **Appearance picker** in `View → Appearance` (System / Light / Dark)
- **Live updates** — alive hosts stream into the table as they're discovered
- **Status bar** — progress, alive count, filter match, elapsed time
- Sandbox disabled (required for ICMP / ARP / raw socket access)

---

## Installation

Download the latest `.dmg` from [Releases](https://github.com/canberkys/iPScanner/releases), open, and drag `iPScanner.app` into `Applications`.

**First launch (Gatekeeper):** the app is currently distributed without an Apple Developer ID signature. To remove the quarantine attribute:

```bash
xattr -d com.apple.quarantine /Applications/iPScanner.app
```

…or right-click the app in Finder → **Open** → **Open** (only required the first time).

> ⚠️ iPScanner runs without sandboxing because network discovery requires direct ICMP / ARP / TCP socket access. All operations stay local — no telemetry, no third-party calls.

---

## Build from source

**Requirements**: macOS 14.4+, Xcode 15+, [xcodegen](https://github.com/yonki/xcodegen)

```bash
brew install xcodegen
git clone https://github.com/canberkys/iPScanner.git
cd iPScanner
xcodegen generate
open iPScanner.xcodeproj
# Cmd+R to build and run
```

The IEEE OUI databases (`oui.txt`, `oui28.txt`, `oui36.txt`) are bundled in the repo. The release CI workflow refreshes them from `standards-oui.ieee.org` on every tag push.

### Run tests

```bash
xcodebuild test -scheme iPScanner -destination 'platform=macOS'
```

85+ unit tests cover the parsers (CIDR/range, ports), OUI 3-tier vendor lookup, CSV escaping, snapshot encode/decode, snapshot diff, device classifier, and saved-range model.

---

## Roadmap

Completed in v1.0:

- [x] Multi-range scan input
- [x] TCP fallback probe (ICMP-blocked hosts)
- [x] mDNS / Bonjour discovery
- [x] Wake-on-LAN
- [x] Saved ranges with names + Rename
- [x] Snapshot save/load (`.ipscan.json`)
- [x] Per-host labels (MAC-anchored, `#tag` searchable)
- [x] Live ping monitor in inspector
- [x] Service-name column for ports (22 → ssh, 9100 → printer, …)
- [x] HTTP title / SSH banner enrichment
- [x] OUI MA-L + MA-M + MA-S (sub-block accuracy)
- [x] App-menu commands + keyboard shortcuts
- [x] Appearance picker (System / Light / Dark)

Completed in v1.1:

- [x] Scan profiles — Quick (ping-only) / Standard (+ TCP fallback) / Deep (+ auto port scan & banner fetch)
- [x] Network interface picker — choose en0 / en1 / utun (VPN) explicitly with subnet auto-fill
- [x] Auto-rescan — off / 30s / 1m / 5m / 15m
- [x] Change detection — load a previous snapshot as comparison baseline; row badges + summary popover (+new / ~changed / -missing)
- [x] Permission/failure surfacing — status-bar warnings hub (ARP empty, banner fetch failures)
- [x] Search match highlighting — query substrings highlighted in IP / Hostname / Vendor / Title / Label cells
- [x] Resizable inspector — drag the inspector divider, width is persisted

Planned for v1.2+:

- [ ] Menu-bar mode with new-device notifications
- [ ] IPv6 support
- [ ] Notarized release with Apple Developer ID

---

## Tech stack

- SwiftUI (macOS 14.4+, `@Observable`, `NavigationSplitView`, `Inspector`)
- Swift Concurrency (`async/await`, `TaskGroup`, `AsyncStream`)
- Network framework — `NWConnection` (TCP probes), `NWBrowser` (Bonjour)
- `Process` for `/sbin/ping`, `/usr/sbin/arp`, Terminal launchers
- Zero third-party Swift packages

---

## License

MIT — see [LICENSE](LICENSE)

Vendor data: [IEEE Standards Association OUI registries](https://standards-oui.ieee.org/) (public)

---

## Author

**Canberk Kılıçarslan** — [canberkki.com](https://canberkki.com)

Feedback, bug reports, and pull requests welcome.
