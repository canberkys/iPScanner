import SwiftUI

// View composition lives here; state and file actions stay in ContentView.
extension ContentView {
    @ViewBuilder
    var toolbar: some View {
        HStack(spacing: 10) {
            if let imported = controller.importedTargets {
                importedChip(imported)
            } else {
                TextField("IP address or range", text: $controller.rangeInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, maxWidth: .infinity)
                    .accessibilityLabel("Scan target range")
                    .onSubmit { if controller.canStart { controller.start() } }
                    .disabled(controller.isScanning)
                Button { controller.toggleSaveCurrentRange() } label: {
                    Image(systemName: controller.isCurrentRangeSaved ? "star.fill" : "star")
                }
                .help("Save or remove this range")
                .accessibilityLabel("Save or remove this range")
                .disabled(controller.rangeInput.isEmpty)
            }
            Menu {
                ForEach(NetworkInterface.scannableInterfaces(), id: \.name) { iface in
                    Button("\(iface.name) — \(iface.ipv4)/\(iface.netmaskBits)") {
                        controller.clearImportedFile()
                        controller.rangeInput = NetworkInterface.subnet(from: iface) ?? ""
                    }
                }
            } label: { Image(systemName: "network") }
            .help("Use a network's subnet")
            .accessibilityLabel("Network subnet")
            .disabled(controller.isScanning)
            if controller.isScanning {
                Button("Stop", systemImage: "stop.fill") { controller.stop() }
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button("Scan", systemImage: "play.fill") { controller.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!controller.canStart)
            }
            Menu {
                Picker("Profile", selection: profileBinding) {
                    ForEach(ScanProfile.allCases) { profile in
                        Text("\(profile.label) — \(profile == .quick ? "Fast ping check" : profile == .standard ? "Recommended discovery" : "Discovery, ports & banners")").tag(profile)
                    }
                }
                .disabled(controller.isScanning)
                Picker("Auto-rescan", selection: rescanBinding) {
                    ForEach(RescanInterval.allCases) { Text($0.menuLabel).tag($0) }
                }
            } label: { Label("Options", systemImage: "slider.horizontal.3").labelStyle(.iconOnly) }
            .help("Scan profile and automatic rescan")
            Menu {
                Button("Import Targets…", action: openTargetFile).disabled(controller.isScanning)
                Button("Subnet Calculator…") {
                    if subnetCalcInput.isEmpty { subnetCalcInput = controller.rangeInput }
                    showingSubnetCalc = true
                }
                Button("Port Scan…") { beginPortScan(ids: controller.selection) }
                    .disabled(controller.selection.isEmpty || controller.isScanning)
            } label: { Label("Tools", systemImage: "wrench.and.screwdriver").labelStyle(.iconOnly) }
            .help("Tools: import targets, calculate a subnet or scan ports")
            .popover(isPresented: $showingSubnetCalc) { subnetCalcPopover }
            .popover(isPresented: $showingPortScan) { portScanPopover }
        }
        .controlSize(.small)
        .padding(12)
    }

    @ViewBuilder
    var resultsToolbar: some View {
        HStack(spacing: 10) {
            if !controller.hosts.isEmpty {
                TextField("", text: $controller.searchQuery, prompt: Text("Search…"))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 70, maxWidth: 200)
                    .focused($searchFieldFocused)
                    .accessibilityLabel("Search devices")

                Menu {
                    Toggle("Unresponsive hosts", isOn: $controller.showDeadHosts)
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
                .help(controller.hasActiveScopeFilters ? controller.activeFilterNames.joined(separator: ", ") : "Filters")
                .accessibilityLabel("Filters")

                if controller.hasActiveScopeFilters {
                    Button("Clear filters (\(controller.activeFilterNames.count))") {
                        controller.clearScopeFilters()
                    }
                    .help(controller.activeFilterNames.joined(separator: ", "))
                }

                // Hidden ⌘C handler — receives keyboard shortcut without taking visual space.
                Button("") { copySelectedIPs() }
                    .keyboardShortcut("c", modifiers: [.command])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)

                Menu {
                    Toggle("Label", isOn: $showColLabel)
                    Toggle("Hostname", isOn: $showColHostname)
                    Toggle("mDNS Name", isOn: $showColMDNSName)
                    Toggle("SMB Name", isOn: $showColSMBName)
                    Toggle("Identification", isOn: $showColIdentification)
                    Toggle("DNS Name", isOn: $showColDNSName)
                    Toggle("SMB Domain", isOn: $showColSMBDomain)
                    Toggle("IPv6 Local", isOn: $showColIPv6Local)
                    Toggle("IPv6 Global", isOn: $showColIPv6Global)
                    Toggle("MAC", isOn: $showColMAC)
                    Toggle("Vendor", isOn: $showColVendor)
                    Toggle("Title", isOn: $showColTitle)
                    Toggle("RTT", isOn: $showColRTT)
                    Toggle("TTL", isOn: $showColTTL)
                    Toggle("Ports", isOn: $showColPorts)
                    Divider()
                    Button("Show All") {
                        showColLabel = true; showColHostname = true; showColMAC = true
                        showColVendor = true; showColTitle = true; showColRTT = true
                        showColTTL = true; showColPorts = true
                        showColMDNSName = true; showColSMBName = true; showColIdentification = true
                        showColDNSName = true; showColSMBDomain = true; showColIPv6Local = true; showColIPv6Global = true
                    }
                    Button("Reset to Default") {
                        showColLabel = true; showColHostname = true; showColMAC = false
                        showColVendor = true; showColTitle = false; showColRTT = false
                        showColTTL = false; showColPorts = true
                        showColMDNSName = true; showColSMBName = true; showColIdentification = true
                        showColDNSName = true; showColSMBDomain = true; showColIPv6Local = true; showColIPv6Global = true
                    }
                } label: {
                    Image(systemName: "rectangle.split.3x1")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Show / hide columns")
                .accessibilityLabel("Column visibility")
            }
            if !controller.hosts.isEmpty {
                Menu {
                    Button("Save as CSV…") { saveCSV() }
                    Button("Save as JSON…") { saveJSON() }
                    Button("Save as IP:Port List…") { saveIPPort() }
                    Button("Save as Text Report…") { saveTextReport() }
                    Divider()
                    Button("Copy to Clipboard (CSV)") { copyCSV() }
                    Button("Copy to Clipboard (JSON)") { copyJSON() }
                    Button("Copy to Clipboard (IP:Port)") { copyIPPort() }
                    Button("Copy to Clipboard (Text Report)") { copyTextReport() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }


            Button { inspectorPresented.toggle() } label: {
                Image(systemName: "sidebar.right")
            }
            .disabled(inspectedHost == nil)
            .help(inspectorPresented ? "Hide device details" : "Show device details")
            .accessibilityLabel("Toggle device details")
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }


}
