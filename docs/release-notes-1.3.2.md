# iPScanner 1.3.2

Released 2026-11-24. A patch for scan accuracy, data safety and security.

## Fixed

- Devices that block ping but refuse a TCP connection are now listed as responding. The fallback response time is the time to the first answer.
- If `/sbin/ping` cannot run, iPScanner says so instead of marking every address unresponsive. The CLI prints a warning and exits with code 2.
- Port scans keep earlier results for ports outside the scanned set.
- Refreshing a device keeps its known MAC address, label and vendor when the ARP table has no entry.
- Opening a scan file shows its labels without saving them and asks whether to keep them. Return chooses Not Now.
- Unreadable saved labels or networks are backed up and reported instead of being overwritten.
- Scan files from a newer format version show a clear message. Snapshots of imported target lists record those targets.
- Wake-on-LAN enables broadcast on its socket and also sends to each local subnet's broadcast address.
- Menu commands act on the front window only and are disabled when they do nothing. New Window (⌘N) is back.
- ⌘C copies selected IP addresses only from the device table; text fields copy normally.
- NetBIOS lookups release their connection on failure and stop when a scan is cancelled.

## Security

- Only canonical dotted-decimal IPv4 addresses are accepted, so a crafted scan file cannot show one address while a connection tool reaches another.
- CSV exports neutralize spreadsheet formulas.
- Web title checks follow redirects only on the same device, and the app-wide network exception is limited to local networking.
- Terminal helper scripts delete themselves after starting.

## Update and compatibility

**Install this version manually once.** The update signing key changed, so
iPScanner 1.3.0 and 1.3.1 cannot install 1.3.2 by themselves. **Check for
Updates…** in those versions announces 1.3.2 and opens this page with
**Learn More…**. Download the DMG and drag iPScanner into Applications,
replacing the old copy. Later updates install from inside the app again.

Universal Apple Silicon + Intel; macOS 14.4 deployment target. Developer ID
signed and notarized, with an Ed25519-signed update archive. Existing settings,
labels and snapshot formats are retained.

## Validation and limitations

217 automated application tests and 9 feedback relay tests passed, including 16
new regression tests. Menu commands, copying, the label prompt and local web
titles were checked in the running app. Wake-on-LAN has not yet been confirmed
on a physical device. iPScanner 1.3.1 was checked against a test feed and showed the
1.3.2 announcement with Learn More instead of an install error.
