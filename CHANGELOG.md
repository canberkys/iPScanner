# Changelog

All notable changes to iPScanner are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Add mDNS Name, SMB Name, Identification, DNS Name, SMB Domain, IPv6 Local and IPv6 Global columns. Hostname now falls back to the mDNS name, then the NetBIOS name, then the device's web page title when reverse DNS returns nothing (common on home networks).
- Look up each device's mDNS name directly (reverse PTR query to UDP 5353) instead of relying on Bonjour service browsing, so devices that advertise no services are named too.
- Show a device model (for example `Mac16,10`) or printer name in Identification, read from Bonjour TXT records.
- Fall back to an inferred vendor ("Apple, Inc.") for devices whose MAC prefix is missing from the bundled vendor list but that identify themselves as Apple.
- Let columns be dragged into a new order; the order is saved between launches.
- Discover IPv6 addresses through a link-local multicast ping and the neighbor table.

### Changed

- Discover hosts with one in-process ICMP socket instead of launching `/sbin/ping` per address, and count devices that answer ARP but drop ping as alive. A /22 scan finds the same devices in roughly a quarter of the time.
- Run the Deep profile's port scan and banner fetch on 32 hosts at a time instead of 4.

### Fixed

- Resolve Bonjour services to IPv4 addresses. Services of other devices resolved to IPv6 and were discarded, so only the scanning Mac's own services appeared.
- Request Bonjour TXT records, which were previously always empty.

## [1.3.1] — 2026-09-28

### Fixed

- Restore Add Label / Edit Label in the device context menu; preserve labels when MAC information arrives later and when saving snapshots.
- Keep scan controls at the top and status at the bottom when no rows are visible; explain active filters while discovery continues.
- Bound ping process duration and skip ping name resolution so unresponsive addresses cannot prolong discovery unnecessarily.
- Scan the right-clicked port-scan targets and disable the action while another scan is active.
- Clear imported targets when selecting a saved network.
- Exclude previously unresponsive targets from missing-device comparisons, normalize MAC badge keys, and refresh comparisons after loading, deleting or refreshing devices.
- Show file-save failures and synchronize externally changed labels with the device inspector.

### Changed

- Present installation in a compact branded disk-image window with a clear drag-to-Applications guide and Retina artwork.

- Align repository metadata and documentation with the published signed release and Sparkle updates.
- Add contributor and support guides, clarify public feedback, and update issue and pull request templates.

### Removed

- Remove obsolete artwork, unused demo frames and superseded development notes; keep current screenshots and release validation in one place.

## [1.3.0] — 2026-09-26

### Added (New)

- Add Sparkle update checks and signed in-app installation, with shared Settings and menu controls. The public feed delivers future releases.
- Run application tests and package validation on pull requests and pushes to main.
- Explain vendor lookup outcomes and the evidence behind estimated device types.
- Preserve optional vendor-status metadata in JSON exports and scan snapshots.

- Native help topics for first scans, profiles, troubleshooting, snapshots and shortcuts.
- Feedback drafts for bugs and feature requests, with optional environment details,
  preview, clipboard fallback and direct Cloudflare delivery to public GitHub issues.
- Settings for scan profile, appearance and automatic update checks, with manual
  checks available in Help and Settings.

### Changed

- Refresh the radar app icon and present the device table, details and export in a short optional tour.
- Refresh the GitHub overview with a captioned UI walkthrough, current light/dark screenshots and a downloadable sample snapshot.
- Ship a validated compact IEEE prefix index instead of raw registry address files.
- Move legacy AFP/Telnet connections and raw vendor database access into Advanced.
- Show connection launch failures and distinguish Wake-on-LAN packet delivery from wake confirmation.

- Load IEEE assignment records without running regular expressions on every
  address line, reducing the initial vendor database loading delay.
- Compact two-row controls, optional saved-ranges sidebar and explicit device details.
- Device details adapt between a sheet and a side panel; minimum window is 800 × 540.
- CLI moves to `Contents/Helpers/ipscanner` and builds as `ipscanner-cli` to prevent
  case-insensitive filename collisions with the GUI executable (#10).
- Release builds require Developer ID, Hardened Runtime, notarization, stapling,
  architecture checks, final DMG validation and SHA-256 checksums. CI prepares drafts.
- Deep discovery, ports and banners share one cancellable lifecycle; rescans wait
  for every phase and stale results cannot overwrite a later run or snapshot.
- Imported targets can start and rescan with an empty range input.


### Security
- Snapshot (`.ipscan.json`) `ip` fields are now validated as IPv4 on decode, and
  `HostActions` guards the same fields again before shelling out — a crafted
  snapshot could previously inject arbitrary shell commands via the SSH /
  Telnet / Ping-in-Terminal / RDP actions.

### Fixed
- Verify universal slices consistently during signed packaging and accept a certificate fingerprint when a signing name contains non-ASCII characters.
- Preserve labels saved with short ARP MAC addresses and avoid false snapshot changes caused by MAC formatting.
- Keep pending label edits attached to the original device when selection changes.
- Explain macOS 27 MAC access restrictions when ARP returns no records.
- Validate complete MAC addresses across common formats; never infer a vendor from locally administered or group addresses.
- Clear stale device enrichment on refresh and retain historical status for saved information.
- Stop classifying phones and Macs as routers merely because their DNS suffix contains hgw.
- Remove vanished Bonjour services and reject stale resolutions after a browse restart.
- Bound ARP execution and report command, parsing and timeout errors separately.

- Large CIDR/range inputs (GUI, CLI, and file import) are now bounds-checked
  *before* expanding into an address list, instead of after — a `/8` or wider
  range could previously exhaust memory before the existing target-count limit
  ever ran.
- Snapshot save/load now preserves each host's alive/dead status instead of
  marking everything alive on reload, and no longer crashes on a snapshot
  containing duplicate IPs or MACs.
- `DNSResolver.reverseLookup`'s timeout now actually bounds wall-clock time;
  previously Swift's structured-concurrency rules meant the function still
  waited for the underlying blocking `getnameinfo()` call to finish even after
  the timeout "won".
- `PortScanner.probe` now stops enqueueing new ports once its `Task` is
  cancelled, instead of draining the full port list one timeout window at a
  time after Stop is pressed.
- `NetBIOSResolver` no longer assumes every NBSTAT response echoes back a
  question section — real Windows/Samba responses typically set `QDCOUNT = 0`.
- The Deep profile's auto banner-fetch now targets the hosts that were
  actually port-scanned instead of the UI's current row selection (previously
  no banners were fetched at all if nothing was selected), and the snapshot
  diff is recomputed after the deep port/banner pass completes so newly found
  open ports show up in change badges.
- The CLI now matches the GUI's Deep-profile behavior (auto port scan +
  banner fetch without requiring `--ports`), preserves NetBIOS
  name/workgroup when merging host records, and its CSV/JSON export now
  includes NetBIOS name, workgroup, service title, and host status —
  previously dropped from every export format.
- `build-dmg.sh` now bundles the `ipscanner` CLI into the app the same way the
  release CI does, so local and CI-built DMGs no longer differ.
- Release CI now syncs `MARKETING_VERSION` from the pushed tag instead of
  relying on a manual version-bump commit.
- The custom About panel no longer hardcodes its version string — it now
  reads `CFBundleShortVersionString` from the bundle, so it can't drift from
  what CI actually shipped.
- The toolbar's range and search fields now have a `minWidth`, so a crowded
  toolbar state (Deep profile + live scan results, at the app's own minimum
  window width) no longer squeezes the range input down to a few pixels —
  confirmed live: it previously collapsed to ~15pt, now holds a usable width
  and any residual overflow clips a less-essential control instead.


## [1.2.0] - 2026-04-27
File import, TTL column, IP:Port/TXT export, `ipscanner` CLI, NetBIOS name
fetcher, subnet calculator popover, in-app update check.

## [1.1.0] - 2026-04-27
Scan profiles, network interface picker, auto-rescan, snapshot diff,
permission/failure warnings hub, search highlighting, resizable inspector.
