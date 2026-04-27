import Foundation

/// Hand-rolled argument parser for `ipscanner`. Avoids pulling in
/// swift-argument-parser to keep the project's "zero third-party packages" promise.
///
/// Usage:
///   ipscanner scan <range>       [options]
///   ipscanner scan --input FILE  [options]
///
/// Options:
///   --profile quick|standard|deep   (default: standard)
///   --ports 22,80,443[,1024-2048]   (no port scan if omitted)
///   --fetch-banners                 (HTTP title / SSH greeting on relevant ports)
///   --format json|csv|txt|ip-port   (default: json)
///   --output PATH                   (default: stdout)
///   --quiet                         (suppress progress on stderr)
///   --help                          (print usage and exit 0)
struct Arguments: Equatable {
    enum OutputFormat: String, CaseIterable {
        case json, csv, txt, ipPort = "ip-port"
    }

    var range: String?
    var inputFile: String?
    var profile: ScanProfile
    var ports: [Int]?
    var fetchBanners: Bool
    var format: OutputFormat
    var output: String?
    var quiet: Bool
    var help: Bool

    static let usage = """
    ipscanner — native macOS network scanner (CLI)

    USAGE:
      ipscanner scan <range>       [options]
      ipscanner scan --input FILE  [options]

    OPTIONS:
      --profile <quick|standard|deep>   Scan depth (default: standard)
      --ports   <list>                  Comma-separated ports / ranges (e.g. 22,80,8000-8100)
      --fetch-banners                   Pull HTTP titles / SSH banners on alive hosts
      --format  <json|csv|txt|ip-port>  Output format (default: json)
      --output  <path>                  Write to file instead of stdout
      --quiet                           Suppress progress on stderr
      --help                            Print this message

    EXIT CODES:
      0  Success
      1  Argument / input error
      2  Runtime / scan error
    """

    /// Parses argv excluding the executable path and the optional subcommand
    /// (we accept `ipscanner <range>` and `ipscanner scan <range>` for convenience).
    static func parse(_ argv: [String]) throws -> Arguments {
        var args = argv
        // Drop a leading "scan" subcommand if present.
        if args.first == "scan" { args.removeFirst() }

        var range: String?
        var inputFile: String?
        var profile: ScanProfile = .standard
        var ports: [Int]?
        var fetchBanners = false
        var format: OutputFormat = .json
        var output: String?
        var quiet = false
        var help = false

        var i = 0
        while i < args.count {
            let token = args[i]
            switch token {
            case "--help", "-h":
                help = true
                i += 1

            case "--input":
                guard let next = args[safe: i + 1] else {
                    throw ParseError.missingValue("--input")
                }
                inputFile = next
                i += 2

            case "--profile":
                guard let next = args[safe: i + 1] else {
                    throw ParseError.missingValue("--profile")
                }
                guard let p = ScanProfile(rawValue: next) else {
                    throw ParseError.invalidValue("--profile", next, "expected one of: quick, standard, deep")
                }
                profile = p
                i += 2

            case "--ports":
                guard let next = args[safe: i + 1] else {
                    throw ParseError.missingValue("--ports")
                }
                guard let parsed = PortScanner.parsePorts(next) else {
                    throw ParseError.invalidValue("--ports", next, "expected e.g. 22,80,8000-8100")
                }
                ports = parsed
                i += 2

            case "--fetch-banners":
                fetchBanners = true
                i += 1

            case "--format":
                guard let next = args[safe: i + 1] else {
                    throw ParseError.missingValue("--format")
                }
                guard let f = OutputFormat(rawValue: next) else {
                    throw ParseError.invalidValue("--format", next, "expected one of: json, csv, txt, ip-port")
                }
                format = f
                i += 2

            case "--output":
                guard let next = args[safe: i + 1] else {
                    throw ParseError.missingValue("--output")
                }
                output = next
                i += 2

            case "--quiet":
                quiet = true
                i += 1

            default:
                if token.hasPrefix("-") {
                    throw ParseError.unknownFlag(token)
                }
                // First positional becomes the range
                if range == nil {
                    range = token
                } else {
                    throw ParseError.unexpectedArgument(token)
                }
                i += 1
            }
        }

        return Arguments(
            range: range,
            inputFile: inputFile,
            profile: profile,
            ports: ports,
            fetchBanners: fetchBanners,
            format: format,
            output: output,
            quiet: quiet,
            help: help
        )
    }

    enum ParseError: Error, Equatable, LocalizedError {
        case missingValue(String)
        case invalidValue(String, String, String)
        case unknownFlag(String)
        case unexpectedArgument(String)
        case missingRange

        var errorDescription: String? {
            switch self {
            case .missingValue(let flag):
                return "Option \(flag) requires a value."
            case .invalidValue(let flag, let value, let hint):
                return "\(flag): invalid value \"\(value)\" — \(hint)"
            case .unknownFlag(let flag):
                return "Unknown flag \(flag). Run with --help for usage."
            case .unexpectedArgument(let arg):
                return "Unexpected extra argument \"\(arg)\"."
            case .missingRange:
                return "No range or --input file supplied. Run with --help for usage."
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
