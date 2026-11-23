import Foundation

@main
struct IPScannerCLI {
    static let stderr = FileHandle.standardError

    static func main() async {
        let argv = Array(CommandLine.arguments.dropFirst())

        let args: Arguments
        do {
            args = try Arguments.parse(argv)
        } catch {
            stderr.write(Data("ipscanner: \(error.localizedDescription)\n".utf8))
            exit(1)
        }

        if args.help || argv.isEmpty {
            print(Arguments.usage)
            exit(args.help ? 0 : 1)
        }

        let verbose = !args.quiet

        // Resolve targets
        let targets: [String]
        do {
            targets = try resolveTargets(args: args)
        } catch {
            die(error.localizedDescription, exitCode: 1)
        }

        if targets.isEmpty {
            die("No targets to scan.", exitCode: 1)
        }
        if targets.count > 65_536 {
            die("Total target list too large (\(targets.count)). Narrow the range or split the file.", exitCode: 1)
        }

        if verbose {
            stderr.write(Data("ipscanner: scanning \(targets.count) target\(targets.count == 1 ? "" : "s") (profile: \(args.profile.label.lowercased()))\n".utf8))
        }

        // Discovery + enrichment
        let scanner = NetworkScanner(profile: args.profile)
        var aliveByIP: [String: Host] = [:]
        var lastReportedProgress = 0
        var discoveryIncomplete = false

        for await event in scanner.scan(addresses: targets) {
            switch event {
            case .phase:
                break
            case .progress(let scanned, let total):
                if verbose, scanned - lastReportedProgress >= max(10, total / 20) || scanned == total {
                    stderr.write(Data("[\(scanned)/\(total)]\n".utf8))
                    lastReportedProgress = scanned
                }
            case .host(let host):
                if host.status == .alive {
                    if let existing = aliveByIP[host.ip] {
                        aliveByIP[host.ip] = existing.merged(with: host)
                    } else {
                        aliveByIP[host.ip] = host
                    }
                }
            case .warning(let warning):
                if case .pingUnavailable(let message) = warning {
                    // Not limited to --verbose: without ping, results are incomplete.
                    discoveryIncomplete = true
                    stderr.write(Data("ipscanner: warning: \(message)\n".utf8))
                } else if verbose {
                    stderr.write(Data("warning: \(warning.label)\n".utf8))
                }
            case .done:
                break
            }
        }

        if verbose {
            stderr.write(Data("ipscanner: \(aliveByIP.count) alive host\(aliveByIP.count == 1 ? "" : "s") found\n".utf8))
        }

        // Optional port scan + banner fetch. `--ports` always wins; with no
        // explicit `--ports`, the Deep profile auto-scans the common-ports set
        // with banner fetch — matching the GUI's ScanController.start(), which
        // chains the same auto port scan for Deep so both surfaces produce the
        // same enrichment for the same profile.
        let explicitPorts = args.ports?.isEmpty == false
        let effectivePorts = explicitPorts ? args.ports : (args.profile.autoPortScan ? PortScanner.parsePorts(PortScanner.defaultPortsInput) : nil)
        let effectiveFetchBanners = args.fetchBanners || (!explicitPorts && args.profile.autoPortScan)

        if let ports = effectivePorts, !ports.isEmpty, !aliveByIP.isEmpty {
            if verbose {
                stderr.write(Data("ipscanner: port-scanning \(aliveByIP.count) host\(aliveByIP.count == 1 ? "" : "s") for \(ports.count) port\(ports.count == 1 ? "" : "s")\n".utf8))
            }
            await runPortScan(hosts: &aliveByIP, ports: ports, fetchBanners: effectiveFetchBanners)
        } else if args.fetchBanners, explicitPorts == false, verbose {
            stderr.write(Data("warning: --fetch-banners requires --ports (or --profile deep); skipping banner fetch\n".utf8))
        }

        // Sort + format + emit
        let sorted = aliveByIP.values.sorted { lhs, rhs in
            (IPv4.uint32(from: lhs.ip) ?? 0) < (IPv4.uint32(from: rhs.ip) ?? 0)
        }
        let rows = ExportService.rows(from: sorted, label: { _ in nil })

        let outputString: String
        do {
            outputString = try render(
                rows: rows,
                format: args.format,
                rangeLabel: rangeLabel(args: args),
                scannedTotal: targets.count,
                aliveCount: aliveByIP.count
            )
        } catch {
            die("Output rendering failed: \(error.localizedDescription)", exitCode: 2)
        }

        if let outPath = args.output {
            do {
                try outputString.write(toFile: outPath, atomically: true, encoding: .utf8)
            } catch {
                die("Could not write to \(outPath): \(error.localizedDescription)", exitCode: 2)
            }
        } else {
            print(outputString, terminator: "")
        }

        // Results were still written, but exit 2 tells scripts discovery was incomplete.
        exit(discoveryIncomplete ? 2 : 0)
    }

    // MARK: - Helpers

    private static func die(_ message: String, exitCode: Int32) -> Never {
        stderr.write(Data("ipscanner: \(message)\n".utf8))
        exit(exitCode)
    }

    private static func resolveTargets(args: Arguments) throws -> [String] {
        if let path = args.inputFile {
            let url = URL(fileURLWithPath: path)
            let result = try TargetFileParser.parse(url: url)
            if !result.invalidLines.isEmpty {
                let n = result.invalidLines.count
                stderr.write(Data("ipscanner: \(n) line\(n == 1 ? "" : "s") in \(url.lastPathComponent) could not be parsed and were skipped\n".utf8))
            }
            return result.targets
        }
        guard let range = args.range else {
            throw Arguments.ParseError.missingRange
        }
        let parsed = ScanRange.parseAll(range)
        if let badIdx = parsed.firstInvalidIndex {
            throw CLIError.invalidRange("Invalid range chunk #\(badIdx) in \"\(range)\"")
        }
        let totalHosts = ScanRange.totalHostCount(parsed.ranges)
        if totalHosts > 65_536 {
            throw CLIError.rangeTooLarge(totalHosts)
        }
        return ScanRange.uniqueAddresses(parsed.ranges)
    }

    private static func rangeLabel(args: Arguments) -> String {
        if let path = args.inputFile {
            return "Imported list: \(URL(fileURLWithPath: path).lastPathComponent)"
        }
        return args.range ?? ""
    }

    private static func runPortScan(hosts: inout [String: Host], ports: [Int], fetchBanners: Bool) async {
        let snapshot = Array(hosts.keys)
        let concurrency = 4

        let portResults: [(String, [Int])] = await withTaskGroup(of: (String, [Int]).self) { group in
            var iter = snapshot.makeIterator()
            for _ in 0..<min(concurrency, snapshot.count) {
                guard let ip = iter.next() else { break }
                group.addTask { (ip, await PortScanner.probe(ip, ports: ports)) }
            }
            var collected: [(String, [Int])] = []
            while let result = await group.next() {
                collected.append(result)
                if let ip = iter.next() {
                    group.addTask { (ip, await PortScanner.probe(ip, ports: ports)) }
                }
            }
            return collected
        }

        for (ip, openPorts) in portResults {
            hosts[ip]?.openPorts = openPorts
        }

        if fetchBanners {
            let bannerTargets: [(String, [Int])] = hosts.values.compactMap { host in
                let relevant = host.openPorts.filter { [80, 443, 22].contains($0) }
                return relevant.isEmpty ? nil : (host.ip, relevant)
            }
            await withTaskGroup(of: (String, String?).self) { group in
                for (ip, openPorts) in bannerTargets {
                    group.addTask { (ip, await BannerProbe.fetch(ip, openPorts: openPorts)) }
                }
                while let (ip, title) = await group.next() {
                    if let title { hosts[ip]?.serviceTitle = title }
                }
            }
        }
    }

    private static func render(
        rows: [ExportService.Row],
        format: Arguments.OutputFormat,
        rangeLabel: String,
        scannedTotal: Int,
        aliveCount: Int
    ) throws -> String {
        switch format {
        case .json:
            let data = try ExportService.json(rows: rows)
            return (String(data: data, encoding: .utf8) ?? "") + "\n"
        case .csv:
            return ExportService.csv(rows: rows)
        case .ipPort:
            return ExportService.ipPortList(rows: rows)
        case .txt:
            return ExportService.textReport(
                rows: rows,
                rangeInput: rangeLabel,
                scannedTotal: scannedTotal,
                aliveCount: aliveCount
            )
        }
    }
}

enum CLIError: Error, LocalizedError {
    case invalidRange(String)
    case rangeTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRange(let msg): return msg
        case .rangeTooLarge(let count):
            return "Total target list too large (\(count) hosts). Narrow the range or split the file."
        }
    }
}
