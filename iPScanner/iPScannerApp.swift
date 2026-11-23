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
    @StateObject private var updater = AppUpdater()
    @Environment(\.openWindow) private var openWindow
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
                Button("iPScanner Help") { openWindow(id: "help") }
                    .keyboardShortcut("?", modifiers: .command)
                Divider()
                Button("iPScanner on GitHub") {
                    if let url = URL(string: "https://github.com/canberkys/iPScanner") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Report an Issue…") { openWindow(id: "feedback") }
                Divider()
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }.disabled(!updater.canCheckForUpdates)
                Divider()
                Menu("Advanced") {
                Button("Open Vendor Database in Finder") {
                    if let url = Bundle.main.url(forResource: "vendors", withExtension: "json") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                }
            }
            ScanMenuCommands()
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
        Settings { ScannerSettingsView(updater: updater) }
        Window("iPScanner Help", id: "help") { ProductHelpView() }
        Window("Feedback", id: "feedback") { FeedbackView() }
            .windowResizability(.contentSize)
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
        string: "\n\nVendor data from IEEE OUI registry.\nBuilt with SwiftUI · Updates powered by Sparkle.",
        attributes: bodyAttrs
    ))

    // Read from the bundle instead of a literal so this panel can't drift from
    // the version CI actually shipped (release.yml syncs MARKETING_VERSION
    // from the git tag at build time).
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "iPScanner",
        .applicationVersion: version,
        .credits: credits,
        .init(rawValue: "Copyright"): "© 2026 Canberk Kılıçarslan"
    ])
    NSApp.activate(ignoringOtherApps: true)
}

/// File-menu scan commands. They live in their own `Commands` type so a change of the
/// focused window's actions re-evaluates only these menus. Reading `@FocusedValue` in
/// the App body re-evaluated the whole scene — and every window's `ContentView` with it,
/// which published new actions again: an endless update loop while a window was key.
struct ScanMenuCommands: Commands {
    /// Actions of the key window only, so a command never runs in every open window.
    @FocusedValue(\.scanCommands) private var scanCommands

    var body: some Commands {
        // Added after New Window (⌘N) instead of replacing it.
        CommandGroup(after: .newItem) {
            Button("Rescan") { scanCommands?.rescan() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(scanCommands?.canRescan != true)

            Divider()

            Button("Open Scan…") { scanCommands?.openSnapshot() }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(scanCommands == nil)

            Button("Save Scan…") { scanCommands?.saveSnapshot() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(scanCommands?.hasResults != true)

            Divider()

            Button("Compare to Scan…") { scanCommands?.compare() }
                .disabled(scanCommands == nil)
            Button("Clear Comparison") { scanCommands?.clearComparison() }
                .disabled(scanCommands?.hasComparison != true)
        }
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Export as CSV…") { scanCommands?.exportCSV() }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(scanCommands?.hasResults != true)
            Button("Export as JSON…") { scanCommands?.exportJSON() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(scanCommands?.hasResults != true)
        }
    }
}

/// Per-window menu actions published by `ContentView` with `focusedSceneValue`.
///
/// Equality ignores the closures: they act on the window's own long-lived state, so two
/// values from the same window with the same flags are interchangeable. Without it every
/// `ContentView` body pass would count as a new focused value and refresh the menus.
struct ScanCommandActions: Equatable {
    var windowID: UUID
    var canRescan: Bool
    var hasResults: Bool
    var hasComparison: Bool
    var rescan: () -> Void
    var openSnapshot: () -> Void
    var saveSnapshot: () -> Void
    var compare: () -> Void
    var clearComparison: () -> Void
    var exportCSV: () -> Void
    var exportJSON: () -> Void

    static func == (lhs: ScanCommandActions, rhs: ScanCommandActions) -> Bool {
        lhs.windowID == rhs.windowID
            && lhs.canRescan == rhs.canRescan
            && lhs.hasResults == rhs.hasResults
            && lhs.hasComparison == rhs.hasComparison
    }
}

private struct ScanCommandsKey: FocusedValueKey {
    typealias Value = ScanCommandActions
}

extension FocusedValues {
    var scanCommands: ScanCommandActions? {
        get { self[ScanCommandsKey.self] }
        set { self[ScanCommandsKey.self] = newValue }
    }
}
