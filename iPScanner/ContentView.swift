import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @AppStorage("iPScanner.sidebarVisible") var sidebarVisible = false
    @Environment(\.openWindow) var openWindow
    @State var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State var inspectorPresented = false
    @State var detailWidth: CGFloat = 800
    @State var controller = ScanController()
    @State var mdns = MDNSDiscovery()
    @State var showingPortScan = false
    @State var portScanTargetIDs: Set<Host.ID> = []
    @State var portsInput = PortScanner.defaultPortsInput
    @State var portError: String?
    @State var fetchBanners = true
    @State var renamingRange: SavedRange?
    @State var labelingHost: Host?
    @State var showingWarnings = false
    @State var showingDiff = false
    @State var importAlert: ImportAlert?
    @State var showingSubnetCalc = false
    @State var subnetCalcInput = ""
    @FocusState var searchFieldFocused: Bool

    struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // Column visibility (persisted) — Status, Device icon, IP always visible.
    /// Lets users drag columns into a new order; saved app-wide so it survives relaunch.
    @State var columnCustomization = ColumnPrefs.load()
    @AppStorage("iPScanner.col.label") var showColLabel = true
    @AppStorage("iPScanner.col.hostname") var showColHostname = true
    @AppStorage("iPScanner.col.mdnsName") var showColMDNSName = true
    @AppStorage("iPScanner.col.smbName") var showColSMBName = true
    @AppStorage("iPScanner.col.identification") var showColIdentification = true
    @AppStorage("iPScanner.col.dnsName") var showColDNSName = true
    @AppStorage("iPScanner.col.smbDomain") var showColSMBDomain = true
    @AppStorage("iPScanner.col.ipv6Local") var showColIPv6Local = true
    @AppStorage("iPScanner.col.ipv6Global") var showColIPv6Global = true
    @AppStorage("iPScanner.col.mac") var showColMAC = false
    @AppStorage("iPScanner.col.vendor") var showColVendor = true
    @AppStorage("iPScanner.col.title") var showColTitle = false
    @AppStorage("iPScanner.col.rtt") var showColRTT = false
    @AppStorage("iPScanner.col.ttl") var showColTTL = false
    @AppStorage("iPScanner.col.ports") var showColPorts = true

    @AppStorage("iPScanner.inspectorWidth") var inspectorWidth: Double = 320
    @AppStorage("iPScanner.scanProfile") var profileRaw: String = ScanProfile.standard.rawValue
    @AppStorage("iPScanner.rescanInterval") var rescanIntervalRaw: String = RescanInterval.off.rawValue

    var profileBinding: Binding<ScanProfile> {
        Binding(
            get: { ScanProfile(rawValue: profileRaw) ?? .standard },
            set: { newValue in
                profileRaw = newValue.rawValue
                controller.profile = newValue
            }
        )
    }

    var rescanBinding: Binding<RescanInterval> {
        Binding(
            get: { RescanInterval(rawValue: rescanIntervalRaw) ?? .off },
            set: { newValue in
                rescanIntervalRaw = newValue.rawValue
                controller.rescanInterval = newValue
            }
        )
    }

    var inspectedHost: Host? {
        guard controller.selection.count == 1,
              let id = controller.selection.first else { return nil }
        return controller.hosts.first { $0.id == id }
    }

    var showInspector: Bool { inspectorPresented && inspectedHost != nil }
    var inspectorSheet: Binding<Bool> {
        Binding(get: { showInspector && detailWidth < 1050 },
                set: { if !$0 { inspectorPresented = false } })
    }
    @ViewBuilder
    var deviceInspector: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Device details").font(.headline)
                Spacer()
                Button { inspectorPresented = false } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close device details")
            }.padding(12)
            HostInspector(
                host: inspectedHost,
                label: inspectedHost.flatMap { controller.label(for: $0) },
                anchor: inspectedHost.map { controller.anchor(for: $0) },
                services: inspectedHost.map { mdns.services(for: $0.ip) } ?? [],
                onLabelChange: { host, value in
                    controller.setLabel(value, for: self.host(forID: host.id) ?? host)
                }
            )
        }
    }

    func diffTint(_ change: HostChange) -> Color {
        switch change {
        case .new: .green
        case .modified: .yellow
        case .missing: .red
        }
    }

    /// Renders text with the active search query highlighted.
    /// Falls through to plain AttributedString when the query is empty or doesn't match.
    func highlighted(_ source: String) -> AttributedString {
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    toolbar.fixedSize(horizontal: false, vertical: true)
                    if !controller.hosts.isEmpty { resultsToolbar }
                    Divider()
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    statusBar.fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector && detailWidth >= 1050 {
                    ResizableDivider(width: $inspectorWidth, minWidth: 260, maxWidth: 360)
                    deviceInspector.frame(width: min(inspectorWidth, 360))
                }
            }
            .background(GeometryReader { geometry in
                Color.clear.onAppear { detailWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in detailWidth = width }
            })
            .navigationSplitViewColumnWidth(min: 560, ideal: 1000)
        }
        .frame(minWidth: 800, minHeight: 540)
        .onChange(of: profileRaw) {
            if !controller.isScanning { controller.profile = ScanProfile(rawValue: profileRaw) ?? .standard }
        }
        .onChange(of: controller.isScanning) { _, active in
            if !active { controller.profile = ScanProfile(rawValue: profileRaw) ?? .standard }
        }
        .sheet(isPresented: inspectorSheet) { deviceInspector.frame(width: 380, height: 500) }
        .onChange(of: columnVisibility) { _, value in sidebarVisible = value != .detailOnly }
        .onChange(of: controller.selection) { _, selection in
            if selection.count != 1 { inspectorPresented = false }
        }
        .onDisappear { controller.stop(); mdns.stop() }
        .onChange(of: columnCustomization) { _, newValue in ColumnPrefs.save(newValue) }
        .onAppear {
            columnVisibility = sidebarVisible ? .all : .detailOnly
            controller.profile = ScanProfile(rawValue: profileRaw) ?? .standard
            controller.rescanInterval = RescanInterval(rawValue: rescanIntervalRaw) ?? .off
            controller.detectDefaultSubnetIfNeeded()
            mdns.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPScannerCommandRescan)) { _ in
            if controller.canStart { controller.start() }
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
        .sheet(item: $labelingHost) { host in
            HostLabelSheet(host: host, initialValue: controller.label(for: host) ?? "") { value in
                // Enrichment may have learned a MAC while the editor was open.
                controller.setLabel(value, for: self.host(forID: host.id) ?? host)
            }
        }
        .sheet(item: $renamingRange) { saved in
            RenameRangeSheet(
                range: saved.range,
                initialName: saved.name ?? ""
            ) { newName in
                controller.renameSavedRange(saved.range, to: newName)
            }
        }
        .alert(item: $importAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    var sidebar: some View {
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
    func savedRangeRow(_ saved: SavedRange) -> some View {
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

    func host(forID id: Host.ID) -> Host? {
        controller.hosts.first { $0.id == id }
    }

    // MARK: - Toolbar

    // MARK: - Subnet calculator popover

    @ViewBuilder
    var subnetCalcPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subnet calculator")
                .font(.headline)

            TextField("CIDR (e.g. 10.0.0.0/24)", text: $subnetCalcInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { /* recompute is automatic */ }

            if let summary = SubnetCalculator.summarize(subnetCalcInput) {
                VStack(alignment: .leading, spacing: 4) {
                    subnetRow("Network",   summary.network)
                    subnetRow("Broadcast", summary.broadcast)
                    if let first = summary.firstHost, let last = summary.lastHost {
                        subnetRow("Hosts", "\(first) → \(last)")
                    } else {
                        subnetRow("Hosts", "—")
                    }
                    subnetRow("Count",     "\(summary.hostCount) usable")
                    subnetRow("Netmask",   summary.netmask)
                    subnetRow("Wildcard",  summary.wildcard)
                }
                .font(.callout)
                .monospacedDigit()

                HStack {
                    Spacer()
                    Button("Use as scan range") {
                        controller.clearImportedFile()
                        controller.rangeInput = summary.cidr
                        showingSubnetCalc = false
                    }
                    .controlSize(.small)
                    .disabled(controller.isScanning)
                }
            } else if !subnetCalcInput.isEmpty {
                Text("Invalid CIDR. Try `10.0.0.0/24`.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Enter an IPv4 CIDR to see network, broadcast, and host range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder
    func subnetRow(_ key: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Imported targets chip

    @ViewBuilder
    func importedChip(_ imported: ScanController.ImportedTargets) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(imported.url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                Text("\(imported.targets.count) target\(imported.targets.count == 1 ? "" : "s")\(imported.invalidLineCount > 0 ? " · \(imported.invalidLineCount) skipped" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                controller.clearImportedFile()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Clear imported list")
            .disabled(controller.isScanning)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.10))
        )
        .frame(maxWidth: 380, alignment: .leading)
    }

    func openTargetFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .commaSeparatedText, .text]
        panel.message = "Select a .txt or .csv file containing IPs, CIDRs, or ranges (one per line; commas allowed)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let summary = try controller.loadImportedFile(url: url)
            if summary.invalidLineCount > 0 {
                importAlert = ImportAlert(
                    title: "Imported with skipped lines",
                    message: "\(summary.targetCount) targets parsed. \(summary.invalidLineCount) line\(summary.invalidLineCount == 1 ? "" : "s") could not be parsed and were skipped."
                )
            }
        } catch {
            importAlert = ImportAlert(
                title: "Could not import",
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    func contextMenu(for ids: Set<Host.ID>) -> some View {
        if ids.count == 1, let id = ids.first, let h = host(forID: id) {
            singleHostMenu(h)
        } else if ids.count > 1 {
            multiHostMenu(ids: ids)
        }
    }

    @ViewBuilder
    func singleHostMenu(_ h: Host) -> some View {
        Button("Show Device Details", systemImage: "sidebar.right") {
            controller.selection = [h.id]
            inspectorPresented = true
        }
        Button(controller.label(for: h) == nil ? "Add Label…" : "Edit Label…", systemImage: "tag") {
            labelingHost = h
        }
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
            Menu("Advanced") {
            Button("Open AFP Share", systemImage: "externaldrive") {
                HostActions.openAFP(ip: h.ip)
            }
            Button("Telnet in Terminal", systemImage: "terminal.fill") {
                HostActions.openTelnet(ip: h.ip)
            }
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
                beginPortScan(ids: [h.id])
            }
            .disabled(controller.isScanning)
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
    func multiHostMenu(ids: Set<Host.ID>) -> some View {
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
            beginPortScan(ids: ids)
        }
        .disabled(controller.isScanning)
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

    // MARK: - Port scan popover

    @ViewBuilder
    var portScanPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Port scan for \(portScanTargetIDs.count) host(s)")
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

    var portPresetBinding: Binding<String> {
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

    func currentRows() -> [ExportService.Row] {
        ExportService.rows(from: controller.filteredHosts) { controller.label(for: $0) }
    }

    func writeExport(_ data: Data, to url: URL) {
        do { try data.write(to: url, options: .atomic) }
        catch {
            importAlert = ImportAlert(title: "Could not save file", message: "Choose a writable location and try again. " + error.localizedDescription)
        }
    }

    func saveCSV() {
        let csv = ExportService.csv(rows: currentRows())
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = ExportService.defaultFileName(ext: "csv")
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            writeExport(Data(csv.utf8), to: url)
        }
    }

    func saveJSON() {
        guard let data = try? ExportService.json(rows: currentRows()) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = ExportService.defaultFileName(ext: "json")
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            writeExport(data, to: url)
        }
    }

    func copyCSV() {
        HostActions.copy(ExportService.csv(rows: currentRows()))
    }

    func copyJSON() {
        guard let data = try? ExportService.json(rows: currentRows()),
              let str = String(data: data, encoding: .utf8) else { return }
        HostActions.copy(str)
    }

    func saveIPPort() {
        let text = ExportService.ipPortList(rows: currentRows())
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = ExportService.defaultFileName(ext: "txt")
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            writeExport(Data(text.utf8), to: url)
        }
    }

    func copyIPPort() {
        HostActions.copy(ExportService.ipPortList(rows: currentRows()))
    }

    func saveTextReport() {
        let text = textReportString()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = ExportService.defaultFileName(ext: "txt")
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            writeExport(Data(text.utf8), to: url)
        }
    }

    func copyTextReport() {
        HostActions.copy(textReportString())
    }

    func textReportString() -> String {
        let rangeLabel: String
        if let imported = controller.importedTargets {
            rangeLabel = "Imported list: \(imported.url.lastPathComponent) (\(imported.targets.count) targets)"
        } else {
            rangeLabel = controller.rangeInput
        }
        let scannedTotal: Int
        switch controller.state {
        case .scanning(_, let total): scannedTotal = total
        case .done(_, let total), .stopped(_, let total): scannedTotal = total
        case .idle: scannedTotal = controller.hosts.count
        }
        return ExportService.textReport(
            rows: currentRows(),
            rangeInput: rangeLabel,
            scannedTotal: scannedTotal,
            aliveCount: controller.aliveCount
        )
    }

    var rttTtlHeader: String {
        switch (showColRTT, showColTTL) {
        case (true, true): "RTT / TTL"
        case (true, false): "RTT"
        case (false, true): "TTL"
        case (false, false): ""
        }
    }

    func rttTtlCell(_ host: Host) -> String {
        var parts: [String] = []
        if showColRTT {
            parts.append(host.rttMs.map { String(format: "%.1f ms", $0) } ?? "—")
        }
        if showColTTL {
            parts.append(host.ttl.map { "ttl \($0)" } ?? "—")
        }
        return parts.joined(separator: " · ")
    }

    /// Rough heuristic translating an ICMP TTL into a probable origin OS.
    /// Real values vary; this is a hint only.
    func ttlHint(for ttl: Int?) -> String {
        guard let ttl else { return "" }
        if ttl >= 250 { return "TTL \(ttl) — likely Cisco / network device" }
        if ttl >= 120 { return "TTL \(ttl) — likely Windows" }
        if ttl >= 60  { return "TTL \(ttl) — likely Linux / macOS / BSD" }
        return "TTL \(ttl)"
    }

    // MARK: - Selection helpers

    func copySelectedIPs() {
        let ips = controller.hosts
            .filter { controller.selection.contains($0.id) }
            .map(\.ip)
        guard !ips.isEmpty else { return }
        HostActions.copy(ips.joined(separator: "\n"))
    }

    // MARK: - Snapshot save / load

    func saveSnapshot() {
        let snapshot = controller.makeSnapshot()
        guard let data = try? SnapshotIO.encode(snapshot) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = SnapshotIO.defaultFileName()
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            writeExport(data, to: url)
        }
    }

    func openSnapshot() {
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

    func openComparisonBaseline() {
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

    struct PortScanEstimate {
        let hosts: Int
        let ports: Int
        let totalProbes: Int
        let estimatedSeconds: Int
        let isHeavy: Bool
    }

    var portScanEstimate: PortScanEstimate? {
        let hosts = portScanTargetIDs.count
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

    func beginPortScan(ids: Set<Host.ID>) {
        guard !controller.isScanning, !ids.isEmpty else { return }
        portScanTargetIDs = ids
        portError = nil
        showingPortScan = true
    }

    func startPortScan() {
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
        controller.runPortScan(ports: ports, fetchBanners: fetchBanners, targetIds: portScanTargetIDs)
    }

    // MARK: - Warnings popover

    @ViewBuilder
    var warningsPopover: some View {
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
    func diffPopover(_ diff: SnapshotDiff) -> some View {
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
