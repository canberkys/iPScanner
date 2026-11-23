<p align="center">
  <img src="assets/icon.png" width="80" alt="iPScanner app icon">
</p>

![iPScanner — native network discovery for macOS](docs/media/header.svg)

<p align="center">
  <a href="https://github.com/canberkys/iPScanner/actions/workflows/ci.yml"><img src="https://github.com/canberkys/iPScanner/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="https://github.com/canberkys/iPScanner/releases"><img src="https://img.shields.io/github/v/release/canberkys/iPScanner?label=published" alt="Latest published version"></a>
  <img src="https://img.shields.io/badge/macOS-14.4%2B-163c5b?logo=apple" alt="macOS deployment target 14.4 and later">
  <img src="https://img.shields.io/badge/Apple_Silicon_%2B_Intel-universal-16728d" alt="Universal binaries">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-24785c" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#demo">Demo</a> · <a href="#get-started">Get started</a> · <a href="docs/features.md">Features</a> · <a href="CHANGELOG.md">Changelog</a> · <a href="https://github.com/canberkys/iPScanner/issues/new/choose">Report an issue</a>
</p>

**iPScanner is a compact, native macOS tool for everyday IPv4 network discovery.**
Find responding devices, inspect names and services, add searchable labels, and
save or export what you find. Built with SwiftUI; signed in-app updates are powered by Sparkle.

> **1.3.1 is available:** [Download the signed, notarized DMG](https://github.com/canberkys/iPScanner/releases/download/v1.3.1/iPScanner-v1.3.1.dmg).
> Fixes the v1.2.0 opening issue ([#10](https://github.com/canberkys/iPScanner/issues/10)).
> See the [release notes](https://github.com/canberkys/iPScanner/releases/tag/v1.3.1)
> for validation details and known platform limitations.

## Demo

![iPScanner device list with names, labels, vendors and open ports](docs/media/results-light.jpg)

<details>
<summary><strong>Watch the short tour: results → device details → export</strong></summary>

![iPScanner results, device details and export walkthrough](docs/media/demo.gif)

An 11-second tour of actual app screens with a fictional saved snapshot. This is
an interface walkthrough, not a live network scan.

</details>

[Screenshot gallery and sample snapshot](docs/media/README.md)

## Everyday tasks, one window

| Task | In iPScanner |
|---|---|
| Discover devices | Enter an IP, CIDR, range or imported target list. Choose Quick, Standard or Deep. |
| Understand a result | Inspect DNS, MAC/vendor status, open ports, Bonjour services and device-type evidence. |
| Find it again | Add labels and #tags, search results, filter the table and save named networks. |
| Compare and share | Save a snapshot, compare changes, or export CSV, JSON, IP:Port and text reports. |
| Connect and troubleshoot | Open connection tools, check live ping, inspect service banners or send Wake-on-LAN. |

<details>
<summary><strong>Light and dark appearances</strong></summary>

| Light | Dark |
|---|---|
| ![Results in light appearance](docs/media/results-light.jpg) | ![Results in dark appearance](docs/media/results-dark.jpg) |

All device names, vendors and labels shown are sample data. [View full-size images](docs/media/README.md).

</details>

## Get started

Download the latest DMG from [Releases](https://github.com/canberkys/iPScanner/releases),
drag **iPScanner** to **Applications**, then open it.

1. Choose your network from the subnet menu or enter a target you administer.
2. Leave the profile on **Standard** and select **Scan**. **Stop** cancels the run.
3. Search the results or select a device and open **Device Details** (`⌘⌥I`).
4. Add a label, save a snapshot or use **Export** above the results.

**Options** contains scan profiles and repeat intervals. **Tools** contains target
import, the subnet calculator and port scans. AFP and Telnet live under **Advanced**.
See [all features](docs/features.md) or open **Help → iPScanner Help** in the app.

### Try the sample without scanning a network

Download [demo.ipscan.json](docs/media/demo.ipscan.json) using GitHub's **Download raw file**
button. In the app, use **File → Open Scan…** (`⌘O`) to load it. Search for `#lab`
to see tag filtering. Loading the snapshot does not start a discovery scan.
Opening details for the first row runs the ping monitor against localhost only.

### Updates and feedback

- **Automatic update checks:** optional daily checks through Sparkle.
  Manual checks are available in Help and Settings.
- **In-app installation:** review release notes, download and install a signed update.
  Install the latest DMG manually once to receive future releases through Sparkle.
- **Feedback:** review your draft in the app before sending it through Cloudflare
  to a **public GitHub issue**. A GitHub account is not required to submit in-app.

### What the results mean

A responding device is observable from your current network; a timeout does not
prove a device is offline. MAC addresses may be unavailable across routers or
because of OS privacy restrictions. Local/randomized MACs do not establish a
manufacturer. Device types are estimates, with evidence in the details view.
Sending a Wake-on-LAN packet does not confirm that a device woke up.

On macOS 27, MAC access may require additional signed capabilities and provisioning.
This remains an [open verification item](docs/acceptance-1.3.0.md).

## Command-line interface

The universal CLI is bundled at `iPScanner.app/Contents/Helpers/ipscanner` and uses
the same discovery engine and export models as the GUI.

```bash
# Quick check of this Mac's loopback address
/Applications/iPScanner.app/Contents/Helpers/ipscanner scan 127.0.0.1 --profile quick

# Scan your target file and write JSON
/Applications/iPScanner.app/Contents/Helpers/ipscanner scan \
  --input targets.csv --profile standard --format json --output scan.json
```

Run `--help` for all options. Exit codes: `0` success, `1` input error, `2` runtime error.
The old `Contents/MacOS/ipscanner` path has moved to avoid the filename collision in #10.

## Build and test

Requirements: macOS, Xcode with an SDK supporting the macOS 14.4 deployment target,
and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/canberkys/iPScanner.git
cd iPScanner
xcodegen generate
open iPScanner.xcodeproj
```

Choose the **iPScanner** scheme and run with `⌘R`.

```bash
xcodebuild test -scheme iPScanner -destination 'platform=macOS' CODE_SIGN_IDENTITY=-
python3 scripts/build-vendor-db.py --check
(cd feedback-relay && npm test)
```

The latest local validation passed **190 application tests and 6 Worker tests**.
See the [acceptance table](docs/acceptance-1.3.0.md) for tested methods and limitations;
a universal build is not proof of testing on Intel hardware or every supported OS.

## Privacy and distribution

- No telemetry. Discovery runs on the targets you select.
- GitHub is contacted for update checks; feedback is sent only when you submit it.
  Scan results, IPs and MACs are not attached to feedback automatically.
- Vendor matching uses a compact offline IEEE index. Raw pinned sources and
  provenance notes are in [data/ieee](data/ieee/).
- Signed packaging validates GUI/CLI identity, architectures, notarization,
  stapling, DMG integrity and SHA-256. [Signing guide](docs/signing-guide-tr.md).

## What's next

The phased roadmap covers urgent fixes (1.3.2), performance and architecture,
interface, accessibility and localization work, new features such as device history,
alerts, a menu-bar mode and IPv6, and CI/test hardening. [Roadmap (Turkish)](docs/roadmap-tr.md).

## Project

[Changelog](CHANGELOG.md) · [1.3.1 notes](docs/release-notes-1.3.1.md) ·
[Bug reports and feature requests](https://github.com/canberkys/iPScanner/issues/new/choose) ·
[Website](https://canberk.me/projects/ipscanner/)

[Contributing](CONTRIBUTING.md) · [Support](SUPPORT.md) · [Update distribution](docs/automatic-updates.md)

MIT © Canberk Kılıçarslan — [LICENSE](LICENSE).
Vendor registry data: [IEEE Standards Association](https://standards-oui.ieee.org/).
