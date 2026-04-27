import Foundation
import AppKit

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
        runInTerminal(name: "ssh-\(ip)", body: "ssh \(ip)\n")
    }

    static func openRDP(ip: String) {
        if let url = URL(string: "rdp://full%20address=s:\(ip)"),
           NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
            return
        }
        // Fallback: write a .rdp file and let LaunchServices pick a handler
        let url = cacheDir.appendingPathComponent("\(ip).rdp")
        let body = """
        full address:s:\(ip)
        screen mode id:i:2
        prompt for credentials:i:1
        """
        try? body.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }

    static func openBrowser(ip: String, scheme: String = "http") {
        guard let url = URL(string: "\(scheme)://\(ip)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openSMB(ip: String) {
        guard let url = URL(string: "smb://\(ip)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openVNC(ip: String) {
        guard let url = URL(string: "vnc://\(ip)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openAFP(ip: String) {
        guard let url = URL(string: "afp://\(ip)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openTelnet(ip: String) {
        runInTerminal(name: "telnet-\(ip)", body: "telnet \(ip)\n")
    }

    static func pingInTerminal(ip: String) {
        runInTerminal(name: "ping-\(ip)", body: "ping \(ip)\n")
    }

    static func wakeOnLAN(mac: String) async {
        try? await WakeOnLAN.wake(mac: mac)
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
        let script = "#!/bin/bash\n\(body)"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        } catch {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
