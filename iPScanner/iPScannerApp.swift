import SwiftUI
import AppKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled.righthalf.striped.horizontal"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@main
struct iPScannerApp: App {
    @AppStorage("iPScanner.appearance") private var appearanceRaw: String = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About iPScanner") {
                    showCustomAboutPanel()
                }
            }
            CommandGroup(replacing: .help) {
                Button("iPScanner on GitHub") {
                    if let url = URL(string: "https://github.com/canberkys/iPScanner") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Report an Issue…") {
                    if let url = URL(string: "https://github.com/canberkys/iPScanner/issues/new") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("Open OUI Database in Finder") {
                    if let url = Bundle.main.url(forResource: "oui", withExtension: "txt") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Rescan") {
                    NotificationCenter.default.post(name: .iPScannerCommandRescan, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Open Scan…") {
                    NotificationCenter.default.post(name: .iPScannerCommandOpenSnapshot, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Save Scan…") {
                    NotificationCenter.default.post(name: .iPScannerCommandSaveSnapshot, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Divider()

                Button("Compare to Scan…") {
                    NotificationCenter.default.post(name: .iPScannerCommandCompareSnapshot, object: nil)
                }
                Button("Clear Comparison") {
                    NotificationCenter.default.post(name: .iPScannerCommandClearComparison, object: nil)
                }
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Export as CSV…") {
                    NotificationCenter.default.post(name: .iPScannerCommandExportCSV, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command])
                Button("Export as JSON…") {
                    NotificationCenter.default.post(name: .iPScannerCommandExportJSON, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

@MainActor
private func showCustomAboutPanel() {
    let credits = NSMutableAttributedString()
    let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.labelColor
    ]
    let linkAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.linkColor,
        .link: URL(string: "https://github.com/canberkys/iPScanner") as Any
    ]

    credits.append(NSAttributedString(
        string: "A native macOS network scanner.\nMIT License.\n\n",
        attributes: bodyAttrs
    ))
    credits.append(NSAttributedString(
        string: "github.com/canberkys/iPScanner",
        attributes: linkAttrs
    ))
    credits.append(NSAttributedString(
        string: "\n\nVendor data from IEEE OUI registry.\nBuilt with SwiftUI · Zero third-party dependencies.",
        attributes: bodyAttrs
    ))

    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "iPScanner",
        .applicationVersion: "1.1.0",
        .credits: credits,
        .init(rawValue: "Copyright"): "© 2026 Canberk Kılıçarslan"
    ])
    NSApp.activate(ignoringOtherApps: true)
}

extension Notification.Name {
    static let iPScannerCommandRescan = Notification.Name("iPScanner.command.rescan")
    static let iPScannerCommandExportCSV = Notification.Name("iPScanner.command.exportCSV")
    static let iPScannerCommandExportJSON = Notification.Name("iPScanner.command.exportJSON")
    static let iPScannerCommandOpenSnapshot = Notification.Name("iPScanner.command.openSnapshot")
    static let iPScannerCommandSaveSnapshot = Notification.Name("iPScanner.command.saveSnapshot")
    static let iPScannerCommandCompareSnapshot = Notification.Name("iPScanner.command.compareSnapshot")
    static let iPScannerCommandClearComparison = Notification.Name("iPScanner.command.clearComparison")
}
