import Foundation
import AppKit

@MainActor
enum HostActions {
    private static var cacheDir: URL {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iPScanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Connect actions

    static func openSSH(ip: String) {
        guard IPv4.uint32(from: ip) != nil else { return }
        runInTerminal(name: "ssh-\(ip)", body: "ssh \(ip)\n")
    }

    static func openRDP(ip: String) {
        guard IPv4.uint32(from: ip) != nil else { return }
        if let url = URL(string: "rdp://full%20address=s:\(ip)"),
           NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            open(url)
            return
        }
        // Fallback: write a .rdp file and let LaunchServices pick a handler
        pruneStaleScripts()
        let url = cacheDir.appendingPathComponent("\(ip).rdp")
        let body = """
        full address:s:\(ip)
        screen mode id:i:2
        prompt for credentials:i:1
        """
        do { try body.write(to: url, atomically: true, encoding: .utf8); open(url) }
        catch { notify("Could not create RDP connection", error.localizedDescription) }
    }

    static func openBrowser(ip: String, scheme: String = "http") {
        guard IPv4.uint32(from: ip) != nil, let url = URL(string: "\(scheme)://\(ip)") else { return }
        open(url)
    }

    static func openSMB(ip: String) {
        guard IPv4.uint32(from: ip) != nil, let url = URL(string: "smb://\(ip)") else { return }
        open(url)
    }

    static func openVNC(ip: String) {
        guard IPv4.uint32(from: ip) != nil, let url = URL(string: "vnc://\(ip)") else { return }
        open(url)
    }

    static func openAFP(ip: String) {
        guard IPv4.uint32(from: ip) != nil, let url = URL(string: "afp://\(ip)") else { return }
        open(url)
    }

    static func openTelnet(ip: String) {
        guard IPv4.uint32(from: ip) != nil else { return }
        runInTerminal(name: "telnet-\(ip)", body: "telnet \(ip)\n")
    }

    static func pingInTerminal(ip: String) {
        guard IPv4.uint32(from: ip) != nil else { return }
        runInTerminal(name: "ping-\(ip)", body: "ping \(ip)\n")
    }

    static func wakeOnLAN(mac: String) async {
        await wakeAll(macs: [mac])
    }

    static func wakeAll(macs: [String]) async {
        let result = await WakeOnLAN.wakeAll(macs: macs)
        notify("Wake-on-LAN", "Packets sent: \(result.sent). Failed: \(result.failed). Sending a packet does not confirm that a device woke up.")
    }

    static func notify(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) }
        else { alert.runModal() }
    }

    private static func open(_ url: URL) {
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            notify("No compatible application", "Install an application that supports this connection type (\(url.pathExtension.isEmpty ? url.scheme ?? "unknown" : url.pathExtension)).")
            return
        }
        if !NSWorkspace.shared.open(url) { notify("Could not open connection", "The selected application could not open this connection.") }
    }

    // MARK: - Clipboard

    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    // MARK: - Internals

    private static func runInTerminal(name: String, body: String) {
        let url = cacheDir.appendingPathComponent("\(name).command")
        let command = body.split(separator: " ").first.map(String.init) ?? ""
        let paths = ["/usr/bin/", "/sbin/", "/opt/homebrew/bin/", "/usr/local/bin/"]
        guard let executable = paths.map({ $0 + command }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            notify("Command unavailable", "The \(command) command is not installed on this Mac.")
            return
        }
        let arguments = body.dropFirst(command.count)
        pruneStaleScripts()
        // The script removes itself once Terminal starts it, so nothing accumulates in Caches.
        let script = "#!/bin/bash\nrm -f -- \"$0\"\n\(executable)\(arguments)"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        } catch {
            notify("Could not prepare command", error.localizedDescription)
            return
        }
        open(url)
    }

    /// Removes `.command` and `.rdp` files left by earlier versions or by scripts that never ran.
    private static func pruneStaleScripts(olderThan age: TimeInterval = 3600) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for file in files where ["command", "rdp"].contains(file.pathExtension) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: file) }
        }
    }
}
