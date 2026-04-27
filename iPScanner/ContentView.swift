import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @State private var controller = ScanController()
    @State private var mdns = MDNSDiscovery()
    @State private var showingPortScan = false
    @State private var portsInput = PortScanner.defaultPortsInput
    @State private var portError: String?
    @State private var fetchBanners = true
    @State private var renamingRange: SavedRange?
    @State private var showingWarnings = false
    @State private var showingDiff = false
    @FocusState private var searchFieldFocused: Bool

    // Column visibility (persisted) — Status, Device icon, IP always visible.
    @AppStorage("iPScanner.col.label") private var showColLabel = true
    @AppStorage("iPScanner.col.hostname") private var showColHostname = true
    @AppStorage("iPScanner.col.mac") private var showColMAC = false
    @AppStorage("iPScanner.col.vendor") private var showColVendor = true
    @AppStorage("iPScanner.col.title") private var showColTitle = false
    @AppStorage("iPScanner.col.rtt") private var showColRTT = false
    @AppStorage("iPScanner.col.ports") private var showColPorts = true

    @AppStorage("iPScanner.inspectorWidth") private var inspectorWidth: Double = 320
    @AppStorage("iPScanner.scanProfile") private var profileRaw: String = ScanProfile.standard.rawValue
    @AppStorage("iPScanner.rescanInterval") private var rescanIntervalRaw: String = RescanInterval.off.rawValue

    private var profileBinding: Binding<ScanProfile> {
        Binding(
            get: { ScanProfile(rawValue: profileRaw) ?? .standard },
            set: { newValue in
                profileRaw = newValue.rawValue
                controller.profile = newValue
            }
        )
    }

    private var rescanBinding: Binding<RescanInterval> {
        Binding(
            get: { RescanInterval(rawValue: rescanIntervalRaw) ?? .off },
            set: { newValue in
                rescanIntervalRaw = newValue.rawValue
                controller.rescanInterval = newValue
            }
        )
    }

    private var inspectedHost: Host? {
        guard controller.selection.count == 1,
              let id = controller.selection.first else { return nil }
        return controller.hosts.first { $0.id == id }
    }

    private var showInspector: Bool { inspectedHost != nil }

    private func diffTint(_ change: HostChange) -> Color {
        switch change {
        case .new: .green
        case .modified: .yellow
        case .missing: .red
        }
    }

    /// Renders text with the active search query highlighted.
    /// Falls through to plain AttributedString when the query is empty or doesn't match.
    private func highlighted(_ source: String) -> AttributedString {
        var attr = AttributedString(source)
        let query = controller.searchQuery
        guard !query.isEmpty,
              let range = attr.range(of: query, options: [.caseInsensitive]) else {
            return attr
        }
        attr[range].backgroundColor = .yellow.opacity(0.4)
        return attr
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    toolbar
                    Divider()
                    content
                    Divider()
                    statusBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector {
                    ResizableDivider(width: $inspectorWidth, minWidth: 260, maxWidth: 460)
                    HostInspector(
                        host: inspectedHost,
                        label: inspectedHost.flatMap { controller.label(for: $0) },
                        anchor: inspectedHost.map { controller.anchor(for: $0) },
                        services: inspectedHost.map { mdns.services(for: $0.ip) } ?? [],
                        onLabelChange: { newValue in
                            if let h = inspectedHost {
                                controller.setLabel(newValue, for: h)
                            }
                        }
                    )
                    .frame(width: inspectorWidth)
                }
            }
            .navigationSplitViewColumnWidth(min: 720, ideal: 1100)
        }
        .frame(minWidth: 960, minHeight: 540)
        .onAppear {
            controller.profile = ScanProfile(rawValue: profileRaw) ?? .standard
            controller.rescanInterval = RescanInterval(rawValue: rescanIntervalRaw) ?? .off
            controller.detectDefaultSubnetIfNeeded()
            mdns.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandRescan)) { _ in
            if !controller.isScanning { controller.start() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandExportCSV)) { _ in
            if !controller.hosts.isEmpty { saveCSV() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandExportJSON)) { _ in
            if !controller.hosts.isEmpty { saveJSON() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandOpenSnapshot)) { _ in
            openSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandSaveSnapshot)) { _ in
            if !controller.hosts.isEmpty { saveSnapshot() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandCompareSnapshot)) { _ in
            openComparisonBaseline()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandClearComparison)) { _ in
            controller.clearComparison()
        }
        .sheet(item: $renamingRange) { saved in
            RenameRangeSheet(
                range: saved.range,
                initialName: saved.name ?? ""
            ) { newName in
                controller.renameSavedRange(saved.range, to: newName)
            }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List {
            Section("Saved Ranges") {
                if controller.savedRanges.isEmpty {
                    Text("No ranges yet.\nUse the ☆ next to the range field to save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(controller.savedRanges) { saved in
                        savedRangeRow(saved)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func savedRangeRow(_ saved: SavedRange) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "network")
                .foregroundStyle(.tint)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                if let name = saved.name, !name.isEmpty {
                    Text(name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(saved.range)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(saved.range)
                        .font(.callout)
                        .monospaced()
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                controller.removeSavedRange(saved.range)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove this range")
            .accessibilityLabel("Remove this range")
        }
        .contentShape(.rect)
        .onTapGesture {
            controller.loadSavedRange(saved.range)
        }
        .contextMenu {
            Button("Rename…", systemImage: "pencil") {
                renamingRange = saved
            }
            Button("Remove", systemImage: "trash", role: .destructive) {
                controller.removeSavedRange(saved.range)
            }
        }
    }

    private func host(forID id: Host.ID) -> Host? {
        controller.hosts.first { $0.id == id }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("10.0.0.0/24, 192.168.1.0/24, 172.16.5.50-172.16.5.100", text: $controller.rangeInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 380)
                .onSubmit { if !controller.isScanning { controller.start() } }

            Button {
                controller.toggleSaveCurrentRange()
            } label: {
                Image(systemName: controller.isCurrentRangeSaved ? "star.fill" : "star")
                    .foregroundStyle(controller.isCurrentRangeSaved ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(controller.rangeInput.trimmingCharacters(in: .whitespaces).isEmpty)
            .help(controller.isCurrentRangeSaved ? "Remove from saved" : "Save range")
            .accessibilityLabel(controller.isCurrentRangeSaved ? "Remove from saved" : "Save range")

            Menu {
                let interfaces = NetworkInterface.scannableInterfaces()
                if interfaces.isEmpty {
                    Text("No active interfaces").foregroundStyle(.secondary)
                } else {
                    ForEach(interfaces, id: \.name) { iface in
                        Button {
                            if let subnet = NetworkInterface.subnet(from: iface) {
                                controller.rangeInput = subnet
                            }
                        } label: {
                            Text("\(iface.name) — \(iface.ipv4)/\(iface.netmaskBits)")
                        }
                    }
                }
            } label: {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Pick interface subnet")
            .accessibilityLabel("Pick interface subnet")

            if controller.isScanning {
                Button("Stop", systemImage: "stop.fill") { controller.stop() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(".", modifiers: [.command])
                    .help("Stop scan (⌘.)")
            } else {
                Button("Scan", systemImage: "play.fill") { controller.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(controller.rangeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Start scan (⌘R)")
            }

            Picker("", selection: profileBinding) {
                ForEach(ScanProfile.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .help(profileBinding.wrappedValue.description)
            .disabled(controller.isScanning)

            Menu {
                Picker("Auto-rescan", selection: rescanBinding) {
                    ForEach(RescanInterval.allCases) { i in
                        Text(i.menuLabel).tag(i)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: rescanBinding.wrappedValue == .off
                          ? "arrow.clockwise"
                          : "arrow.clockwise.circle.fill")
                        .foregroundStyle(rescanBinding.wrappedValue == .off ? Color.secondary : Color.accentColor)
                    if rescanBinding.wrappedValue != .off {
                        Text(rescanBinding.wrappedValue.label)
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Auto-rescan interval")
            .accessibilityLabel("Auto-rescan interval")

            if case .scanning(let scanned, let total) = controller.state {
                ProgressView(value: Double(scanned), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .frame(width: 160)
            }

            if !controller.hosts.isEmpty {
                Button {
                    portError = nil
                    showingPortScan = true
                } label: {
                    Label("Port Scan…", systemImage: "network.badge.shield.half.filled")
                }
                .disabled(controller.selection.isEmpty || controller.portScanInProgress || controller.isScanning)
                .popover(isPresented: $showingPortScan, arrowEdge: .bottom) {
                    portScanPopover
                }
            }

            if controller.portScanInProgress {
                HStack(spacing: 6) {
                    ProgressView(
                        value: Double(controller.portScanProgress.scanned),
                        total: Double(max(controller.portScanProgress.total, 1))
                    )
                    .progressViewStyle(.linear)
                    .frame(width: 100)
                    Text("\(controller.portScanProgress.scanned) / \(controller.portScanProgress.total)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button {
                        controller.cancelPortScan()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Cancel port scan")
                }
            }

            if !controller.hosts.isEmpty {
                Menu {
                    Button("Save as CSV…") { saveCSV() }
                    Button("Save as JSON…") { saveJSON() }
                    Divider()
                    Button("Copy to Clipboard (CSV)") { copyCSV() }
                    Button("Copy to Clipboard (JSON)") { copyJSON() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer()

            if !controller.hosts.isEmpty {
                TextField("", text: $controller.searchQuery, prompt: Text("Search…"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .focused($searchFieldFocused)

                Menu {
                    Toggle("Has open ports", isOn: $controller.filterHasOpenPorts)
                    Toggle("Has label", isOn: $controller.filterHasLabel)
                    Toggle("Has vendor", isOn: $controller.filterHasVendor)
                    Toggle("Identified device type", isOn: $controller.filterIdentifiedDevice)
                    if controller.hasActiveScopeFilters {
                        Divider()
                        Button("Clear filters") { controller.clearScopeFilters() }
                    }
                } label: {
                    Image(systemName: controller.hasActiveScopeFilters
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(controller.hasActiveScopeFilters ? Color.accentColor : .secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Filters")
                .accessibilityLabel("Filters")

                Toggle("Dead hosts", isOn: $controller.showDeadHosts)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help("Show unresponsive IPs")

                // Hidden ⌘C handler — receives keyboard shortcut without taking visual space.
                Button("") { copySelectedIPs() }
                    .keyboardShortcut("c", modifiers: [.command])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)

                Menu {
                    Toggle("Label", isOn: $showColLabel)
                    Toggle("Hostname", isOn: $showColHostname)
                    Toggle("MAC", isOn: $showColMAC)
                    Toggle("Vendor", isOn: $showColVendor)
                    Toggle("Title", isOn: $showColTitle)
                    Toggle("RTT", isOn: $showColRTT)
                    Toggle("Ports", isOn: $showColPorts)
                    Divider()
                    Button("Show All") {
                        showColLabel = true; showColHostname = true; showColMAC = true
                        showColVendor = true; showColTitle = true; showColRTT = true
                        showColPorts = true
                    }
                    Button("Reset to Default") {
                        showColLabel = true; showColHostname = true; showColMAC = false
                        showColVendor = true; showColTitle = false; showColRTT = false
                        showColPorts = true
                    }
                } label: {
                    Image(systemName: "rectangle.split.3x1")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Show / hide columns")
                .accessibilityLabel("Column visibility")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if controller.hosts.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(controller.filteredHosts, selection: $controller.selection, sortOrder: $controller.sortOrder) {
                TableColumn("●") { host in
                    Circle()
                        .fill(host.status == .alive ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .help(host.status == .alive ? "Alive" : (host.status == .dead ? "Dead" : "Scanning"))
                        .accessibilityLabel(host.status == .alive ? "Alive" : (host.status == .dead ? "Dead" : "Scanning"))
                }
                .width(20)

                TableColumn("IP", value: \.ipNumeric) { host in
                    let kind = DeviceClassifier.classify(host)
                    HStack(spacing: 6) {
                        Image(systemName: kind.sfSymbol)
                            .font(.caption)
                            .foregroundStyle(kind == .unknown ? Color.secondary.opacity(0.4) : Color.secondary)
                            .help(kind.label)
                            .frame(width: 14, alignment: .center)
                        Text(highlighted(host.ip)).monospaced()
                    }
                }
                .width(min: 130, ideal: 145)

                if controller.diff != nil {
                    TableColumn("Δ") { host in
                        if let change = controller.change(for: host) {
                            Image(systemName: change.sfSymbol)
                                .foregroundStyle(diffTint(change))
                                .help(change.label)
                                .accessibilityLabel(change.label)
                        } else {
                            Text("")
                        }
                    }
                    .width(20)
                }

                if showColLabel {
                    TableColumn("Label") { host in
                        if let label = controller.label(for: host) {
                            Text(highlighted(label)).foregroundStyle(.tint)
                        } else {
                            Text("")
                        }
                    }
                    .width(min: 80, ideal: 130)
                }

                if showColHostname {
                    TableColumn("Hostname") { host in
                        if let h = host.hostname {
                            Text(highlighted(h))
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 110, ideal: 170)
                }

                if showColMAC {
                    TableColumn("MAC") { host in
                        if let m = host.mac {
                            Text(highlighted(m.uppercased())).monospaced()
                        } else {
                            Text("—").monospaced().foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 120, ideal: 140)
                }

                if showColVendor {
                    TableColumn("Vendor") { host in
                        if let v = host.vendor {
                            Text(highlighted(v))
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 100, ideal: 150)
                }

                if showColTitle {
                    TableColumn("Title") { host in
                        if let t = host.serviceTitle {
                            Text(highlighted(t))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(t)
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 80, ideal: 130)
                }

                if showColRTT {
                    TableColumn("RTT") { host in
                        Text(host.rttMs.map { String(format: "%.1f", $0) } ?? "—")
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 50, ideal: 60, max: 80)
                }

                if showColPorts {
                    TableColumn("Ports") { host in
                        Text(PortScanner.formatList(host.openPorts))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 140)
                }
            }
            .frame(maxHeight: .infinity)
            .contextMenu(forSelectionType: Host.ID.self) { ids in
                contextMenu(for: ids)
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first, let h = host(forID: id) {
                    HostActions.openBrowser(ip: h.ip)
                }
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for ids: Set<Host.ID>) -> some View {
        if ids.count == 1, let id = ids.first, let h = host(forID: id) {
            singleHostMenu(h)
        } else if ids.count > 1 {
            multiHostMenu(ids: ids)
        }
    }

    @ViewBuilder
    private func singleHostMenu(_ h: Host) -> some View {
        Section {
            Button("Open in Browser (http)", systemImage: "safari") {
                HostActions.openBrowser(ip: h.ip)
            }
            Button("Open in Browser (https)", systemImage: "lock.shield") {
                HostActions.openBrowser(ip: h.ip, scheme: "https")
            }
            Button("SSH in Terminal", systemImage: "terminal") {
                HostActions.openSSH(ip: h.ip)
            }
            Button("Connect via VNC", systemImage: "rectangle.connected.to.line.below") {
                HostActions.openVNC(ip: h.ip)
            }
            Button("Microsoft Remote Desktop (RDP)", systemImage: "display") {
                HostActions.openRDP(ip: h.ip)
            }
            Button("Open SMB Share", systemImage: "externaldrive.connected.to.line.below") {
                HostActions.openSMB(ip: h.ip)
            }
            Button("Open AFP Share", systemImage: "externaldrive") {
                HostActions.openAFP(ip: h.ip)
            }
            Button("Telnet in Terminal", systemImage: "terminal.fill") {
                HostActions.openTelnet(ip: h.ip)
            }
            Button("Ping in Terminal", systemImage: "wave.3.right") {
                HostActions.pingInTerminal(ip: h.ip)
            }
        }
        Section {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await controller.refreshHost(h.id) }
            }
            if h.mac != nil {
                Button("Wake (Wake-on-LAN)", systemImage: "power.circle.fill") {
                    Task { await controller.runWakeOnLAN(for: [h.id]) }
                }
            }
            Button("Port Scan…", systemImage: "network.badge.shield.half.filled") {
                portError = nil
                showingPortScan = true
            }
        }
        Section {
            Button("Copy IP", systemImage: "doc.on.doc") { HostActions.copy(h.ip) }
            if let host = h.hostname {
                Button("Copy Hostname") { HostActions.copy(host) }
            }
            if let mac = h.mac {
                Button("Copy MAC") { HostActions.copy(mac) }
            }
        }
        Section {
            Button("Remove from List", systemImage: "trash", role: .destructive) {
                controller.deleteHosts([h.id])
            }
        }
    }

    @ViewBuilder
    private func multiHostMenu(ids: Set<Host.ID>) -> some View {
        let hosts = ids.compactMap { host(forID: $0) }
        let wakeable = hosts.filter { $0.mac != nil }.count
        Button("Refresh (\(hosts.count) hosts)", systemImage: "arrow.clockwise") {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for h in hosts {
                        group.addTask { await controller.refreshHost(h.id) }
                    }
                }
            }
        }
        Button("Port Scan… (\(hosts.count) hosts)", systemImage: "network.badge.shield.half.filled") {
            portError = nil
            showingPortScan = true
        }
        if wakeable > 0 {
            Button("Wake (\(wakeable) hosts)", systemImage: "power.circle.fill") {
                Task { await controller.runWakeOnLAN(for: ids) }
            }
        }
        Button("Copy IPs", systemImage: "doc.on.doc") {
            HostActions.copy(hosts.map(\.ip).joined(separator: "\n"))
        }
        Section {
            Button("Remove from List (\(hosts.count) hosts)", systemImage: "trash", role: .destructive) {
                controller.deleteHosts(ids)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let err = controller.lastError {
            ContentUnavailableView {
                Label("iPScanner", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } description: {
                Text(err).foregroundStyle(.red)
            }
        } else {
            let trimmed = controller.rangeInput.trimmingCharacters(in: .whitespaces)
            ContentUnavailableView {
                Label("iPScanner", systemImage: "network")
            } description: {
                if !trimmed.isEmpty {
                    VStack(spacing: 4) {
                        Text("Ready to scan")
                            .foregroundStyle(.secondary)
                        Text(trimmed)
                            .monospaced()
                            .foregroundStyle(.tint)
                        Text("Press Scan or ⌘R")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Enter an IP range and press Scan.")
                }
            }
        }
    }

    // MARK: - Port scan popover

    @ViewBuilder
    private var portScanPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Port scan for \(controller.selection.count) host(s)")
                .font(.headline)

            TextField("Ports", text: $portsInput, prompt: Text("22, 80, 443, 8000-8100"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)

            Picker("Preset", selection: portPresetBinding) {
                Text("Common").tag("common")
                Text("Web").tag("web")
                Text("Remote").tag("remote")
                Text("1-1024").tag("range")
                Text("Custom").tag("custom")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle("Fetch service banners (HTTP/SSH)", isOn: $fetchBanners)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("Query title/banner for hosts with port 80/443/22 open")

            if let estimate = portScanEstimate {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: estimate.isHeavy ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(estimate.isHeavy ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(estimate.hosts) hosts × \(estimate.ports) ports = \(estimate.totalProbes) probes")
                        Text("~\(estimate.estimatedSeconds)s estimated")
                    }
                    .font(.caption)
                    .foregroundStyle(estimate.isHeavy ? .orange : .secondary)
                }
            }

            if let portError {
                Text(portError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { showingPortScan = false }
                    .keyboardShortcut(.cancelAction)
                Button("Scan") { startPortScan() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var portPresetBinding: Binding<String> {
        Binding(
            get: {
                switch portsInput {
                case PortScanner.defaultPortsInput: return "common"
                case "80, 443, 8080, 8443": return "web"
                case "22, 3389, 5900": return "remote"
                case "1-1024": return "range"
                default: return "custom"
                }
            },
            set: { newValue in
                switch newValue {
                case "common": portsInput = PortScanner.defaultPortsInput
                case "web": portsInput = "80, 443, 8080, 8443"
                case "remote": portsInput = "22, 3389, 5900"
                case "range": portsInput = "1-1024"
                default: break
                }
            }
        )
    }

    // MARK: - Export

    private func currentRows() -> [ExportService.Row] {
        ExportService.rows(from: controller.filteredHosts) { controller.label(for: $0) }
    }

    private func saveCSV() {
        let csv = ExportService.csv(rows: currentRows())
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = ExportService.defaultFileName(ext: "csv")
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.data(using: .utf8)?.write(to: url)
        }
    }

    private func saveJSON() {
        guard let data = try? ExportService.json(rows: currentRows()) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = ExportService.defaultFileName(ext: "json")
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func copyCSV() {
        HostActions.copy(ExportService.csv(rows: currentRows()))
    }

    private func copyJSON() {
        guard let data = try? ExportService.json(rows: currentRows()),
              let str = String(data: data, encoding: .utf8) else { return }
        HostActions.copy(str)
    }

    // MARK: - Selection helpers

    private func copySelectedIPs() {
        let ips = controller.hosts
            .filter { controller.selection.contains($0.id) }
            .map(\.ip)
        guard !ips.isEmpty else { return }
        HostActions.copy(ips.joined(separator: "\n"))
    }

    // MARK: - Snapshot save / load

    private func saveSnapshot() {
        let snapshot = controller.makeSnapshot()
        guard let data = try? SnapshotIO.encode(snapshot) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = SnapshotIO.defaultFileName()
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func openSnapshot() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let snapshot = try SnapshotIO.decode(data)
                controller.applySnapshot(snapshot)
            } catch {
                controller.reportError("Failed to read scan file: \(error.localizedDescription)")
            }
        }
    }

    private func openComparisonBaseline() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Pick a previous scan to compare against the current results."
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let snapshot = try SnapshotIO.decode(data)
                controller.loadComparisonBaseline(snapshot)
            } catch {
                controller.reportError("Failed to read comparison file: \(error.localizedDescription)")
            }
        }
    }

    private struct PortScanEstimate {
        let hosts: Int
        let ports: Int
        let totalProbes: Int
        let estimatedSeconds: Int
        let isHeavy: Bool
    }

    private var portScanEstimate: PortScanEstimate? {
        let hosts = controller.selection.count
        guard hosts > 0,
              let parsed = PortScanner.parsePorts(portsInput) else { return nil }
        let ports = parsed.count
        let total = hosts * ports
        // Controller runs `portScanHostConcurrency` hosts in parallel; each host probes
        // `PortScanner.perHostConcurrency` ports in parallel with ~0.8s timeout per port.
        // Total time ≈ ceil(hosts/H) * ceil(ports/P) * 0.8s.
        let hostBatches = Int(ceil(Double(hosts) / Double(ScanController.portScanHostConcurrency)))
        let portBatches = Int(ceil(Double(ports) / Double(PortScanner.perHostConcurrency)))
        let estimated = max(1, hostBatches * portBatches)
        return PortScanEstimate(
            hosts: hosts,
            ports: ports,
            totalProbes: total,
            estimatedSeconds: estimated,
            isHeavy: total > 50_000 || estimated > 60
        )
    }

    private func startPortScan() {
        guard let ports = PortScanner.parsePorts(portsInput) else {
            portError = "Invalid port input (e.g. 22, 80, 443 or 8000-8100)"
            return
        }
        if ports.count > 5000 {
            portError = "Too many ports: \(ports.count). Scans over 5000 ports are slow."
            return
        }
        portError = nil
        showingPortScan = false
        controller.runPortScan(ports: ports, fetchBanners: fetchBanners)
    }

    // MARK: - Warnings popover

    @ViewBuilder
    private var warningsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scan warnings")
                .font(.headline)
            ForEach(Array(controller.warnings.enumerated()), id: \.offset) { _, w in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(w.label)
                            .fontWeight(.medium)
                    }
                    Text(w.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    // MARK: - Diff popover

    @ViewBuilder
    private func diffPopover(_ diff: SnapshotDiff) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Comparison")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    controller.clearComparison()
                    showingDiff = false
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Text("Baseline: \(diff.baselineCreatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Label("\(diff.newCount) new", systemImage: "plus.circle.fill")
                    .foregroundStyle(.green)
                Label("\(diff.modifiedCount) changed", systemImage: "circle.lefthalf.filled")
                    .foregroundStyle(.yellow)
                Label("\(diff.missingCount) missing", systemImage: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .font(.callout)

            if !diff.missingRecords.isEmpty {
                Divider()
                Text("Missing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(diff.missingRecords, id: \.ip) { rec in
                            HStack(spacing: 6) {
                                Text(rec.ip).monospaced()
                                if let host = rec.hostname {
                                    Text(host).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let vendor = rec.vendor {
                                    Text(vendor)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    // MARK: - Status bar

    @ViewBuilder
    private var statusBar: some View {
        HStack(spacing: 16) {
            switch controller.state {
            case .idle:
                Text("Ready")
                    .foregroundStyle(.secondary)
            case .scanning(let scanned, let total):
                Text("\(scanned) of \(total) scanned")
                Text("•").foregroundStyle(.secondary)
                Text("\(controller.aliveCount) alive").foregroundStyle(.green)
            case .done(let scanned, let total):
                Text("Completed: \(scanned) of \(total)")
                Text("•").foregroundStyle(.secondary)
                Text("\(controller.aliveCount) alive").foregroundStyle(.green)
            }
            if !controller.searchQuery.isEmpty && !controller.hosts.isEmpty {
                Text("•").foregroundStyle(.secondary)
                Text("\(controller.filteredHosts.count) of \(controller.hosts.count) match")
                    .foregroundStyle(.tint)
                    .monospacedDigit()
            }
            if !controller.warnings.isEmpty {
                Text("•").foregroundStyle(.secondary)
                Button {
                    showingWarnings.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(controller.warnings.count) warning\(controller.warnings.count == 1 ? "" : "s")")
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingWarnings, arrowEdge: .top) {
                    warningsPopover
                }
            }
            if let diff = controller.diff {
                Text("•").foregroundStyle(.secondary)
                Button {
                    showingDiff.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("+\(diff.newCount) ~\(diff.modifiedCount) -\(diff.missingCount)")
                            .monospacedDigit()
                    }
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help("Comparison vs scan from \(diff.baselineCreatedAt.formatted(date: .abbreviated, time: .shortened))")
                .popover(isPresented: $showingDiff, arrowEdge: .top) {
                    diffPopover(diff)
                }
            }
            Spacer()
            if controller.elapsed > 0 {
                let elapsedFormatted = String(format: "%.1f", controller.elapsed)
                Text("\(elapsedFormatted)s")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 560)
}

// MARK: - Rename saved range sheet

struct RenameRangeSheet: View {
    let range: String
    let initialName: String
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var fieldFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Range")
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Text(range)
                    .monospaced()
                    .font(.callout)
                Text("Add a friendly name (e.g. Home, Office VLAN, Lab)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Name", text: $name, prompt: Text("Optional"))
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocus)
                .onSubmit { save() }

            HStack {
                if !initialName.isEmpty {
                    Button("Clear", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            name = initialName
            fieldFocus = true
        }
    }

    private func save() {
        onSave(name)
        dismiss()
    }
}

// MARK: - Resizable divider

private struct ResizableDivider: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double

    @State private var startWidth: Double?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Divider()
            Rectangle()
                .fill(Color.clear)
                .frame(width: 6)
                .contentShape(.rect)
        }
        .frame(width: 6)
        .onHover { hovering in
            // Push/pop is balanced; onDisappear handles the case where the
            // inspector is removed while the cursor is still inside the area.
            if hovering, !isHovering {
                NSCursor.resizeLeftRight.push()
                isHovering = true
            } else if !hovering, isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
        .onDisappear {
            if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if startWidth == nil { startWidth = width }
                    let proposed = (startWidth ?? width) - Double(value.translation.width)
                    width = min(max(proposed, minWidth), maxWidth)
                }
                .onEnded { _ in startWidth = nil }
        )
    }
}
