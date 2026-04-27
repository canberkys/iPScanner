import Foundation

enum ARPLookup {
    static func table() async -> [String: String] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String: String], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
                process.arguments = ["-an"]
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: [:])
                    return
                }
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: data, encoding: .utf8) ?? ""
                var table: [String: String] = [:]
                for line in output.split(separator: "\n") {
                    if line.contains("(incomplete)") { continue }
                    guard let match = line.firstMatch(of: #/\(([0-9.]+)\)\s+at\s+([0-9a-fA-F:]+)/#) else { continue }
                    let ip = String(match.1)
                    let mac = String(match.2).lowercased()
                    table[ip] = mac
                }
                continuation.resume(returning: table)
            }
        }
    }
}
