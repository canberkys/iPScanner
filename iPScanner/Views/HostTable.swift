import SwiftUI

/// Persists the user's column order and widths in UserDefaults.
enum ColumnPrefs {
    static let key = "iPScanner.tableColumns.v1"

    static func load() -> TableColumnCustomization<iPScanner.Host> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(TableColumnCustomization<iPScanner.Host>.self, from: data)
        else { return TableColumnCustomization<iPScanner.Host>() }
        return saved
    }

    static func save(_ customization: TableColumnCustomization<iPScanner.Host>) {
        if let data = try? JSONEncoder().encode(customization) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// View composition lives here; state and file actions stay in ContentView.
extension ContentView {
    // MARK: - Content

    @ViewBuilder
    var content: some View {
        if controller.hosts.isEmpty || controller.showsDiscoveryEmptyState {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.filteredHosts.isEmpty {
            ContentUnavailableView {
                Label("No matching devices", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(controller.isScanning
                     ? "No devices match yet. Scanning is still in progress; device names, vendors and ports may arrive later."
                     : "Devices were found, but none match the current search and filters.")
                if !controller.activeFilterNames.isEmpty {
                    Text("Filters: " + controller.activeFilterNames.joined(separator: ", "))
                }
            } actions: {
                Button("Clear Search and Filters") {
                    controller.searchQuery = ""
                    controller.clearScopeFilters()
                }
            }
        } else {
            Table(controller.filteredHosts, selection: $controller.selection, sortOrder: $controller.sortOrder, columnCustomization: $columnCustomization) {
                TableColumn("●") { host in
                    Circle()
                        .fill(host.status == .alive ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .help(host.status == .alive ? "Alive" : (host.status == .dead ? "Dead" : "Scanning"))
                        .accessibilityLabel(host.status == .alive ? "Alive" : (host.status == .dead ? "Dead" : "Scanning"))
                }
                .width(20)
                .customizationID("status")

                TableColumn("IP", value: \.ipNumeric) { host in
                    let kind = DeviceClassifier.classify(host)
                    HStack(spacing: 6) {
                        Image(systemName: kind.sfSymbol)
                            .font(.caption)
                            .foregroundStyle(kind == .unknown ? Color.secondary.opacity(0.4) : Color.secondary)
                            .help(DeviceClassifier.assessment(host).evidence)
                            .frame(width: 14, alignment: .center)
                        Text(highlighted(host.ip)).monospaced()
                    }
                }
                .width(min: 130, ideal: 145)
                .customizationID("ip")

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
                    .customizationID("delta")
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
                    .customizationID("label")
                }

                Group {
                    if showColHostname {
                        TableColumn("Hostname") { (host: iPScanner.Host) in
                            if let h = HostNames.preferred(dns: host.hostname, mdns: host.mdnsName ?? mdns.deviceName(for: host.ip), netbios: host.netbiosName) {
                                Text(highlighted(h))
                            } else if let t = host.serviceTitle, !t.hasPrefix("SSH-") {
                                Text(highlighted(t)).foregroundStyle(.secondary)
                                    .help("No hostname found; showing the device's web page title")
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                        .width(min: 110, ideal: 170)
                        .customizationID("hostname")
                    }

                    if showColMDNSName {
                        TableColumn("mDNS Name") { (host: iPScanner.Host) in
                            if let n = host.mdnsName ?? mdns.deviceName(for: host.ip) {
                                Text(highlighted(n))
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                        .width(min: 90, ideal: 140)
                        .customizationID("mdnsName")
                    }

                    if showColIdentification {
                        TableColumn("Identification") { (host: iPScanner.Host) in
                            if let id = mdns.identification(for: host.ip) {
                                Text(highlighted(id)).lineLimit(1).truncationMode(.tail).help(id)
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                        .width(min: 100, ideal: 180)
                        .customizationID("identification")
                    }

                    if showColSMBName {
                        TableColumn("SMB Name") { (host: iPScanner.Host) in
                            if let n = host.netbiosName {
                                Text(highlighted(n))
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                        .width(min: 90, ideal: 120)
                        .customizationID("smbName")
                    }

                    if showColDNSName {
                        TableColumn("DNS Name") { (host: iPScanner.Host) in
                            if let n = host.hostname { Text(highlighted(n)) } else { Text("—").foregroundStyle(.secondary) }
                        }
                        .width(min: 90, ideal: 130)
                        .customizationID("dnsName")
                    }

                    if showColSMBDomain {
                        TableColumn("SMB Domain") { (host: iPScanner.Host) in
                            if let n = host.workgroup { Text(highlighted(n)) } else { Text("—").foregroundStyle(.secondary) }
                        }
                        .width(min: 80, ideal: 110)
                        .customizationID("smbDomain")
                    }

                    if showColIPv6Local {
                        TableColumn("IPv6 Local") { (host: iPScanner.Host) in
                            let a = host.ipv6Addresses.filter(IPv6Neighbors.isLocal)
                            if let t = IPv6Neighbors.summary(a) { Text(t).monospaced().lineLimit(1).truncationMode(.middle).help(a.joined(separator: "\n")) } else { Text("—").foregroundStyle(.secondary) }
                        }
                        .width(min: 120, ideal: 220)
                        .customizationID("ipv6Local")
                    }

                    if showColIPv6Global {
                        TableColumn("IPv6 Global") { (host: iPScanner.Host) in
                            let a = host.ipv6Addresses.filter { !IPv6Neighbors.isLocal($0) }
                            if let t = IPv6Neighbors.summary(a) { Text(t).monospaced().lineLimit(1).truncationMode(.middle).help(a.joined(separator: "\n")) } else { Text("—").foregroundStyle(.secondary) }
                        }
                        .width(min: 120, ideal: 240)
                        .customizationID("ipv6Global")
                    }
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
                    .customizationID("mac")
                }

                if showColVendor {
                    TableColumn("Vendor") { host in
                        let v = HostNames.vendor(
                            registered: host.vendor,
                            names: [host.mdnsName, host.netbiosName, mdns.deviceName(for: host.ip)],
                            serviceTypes: mdns.services(for: host.ip).map(\.serviceType))
                        if let v {
                            Text(highlighted(v))
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 100, ideal: 150)
                    .customizationID("vendor")
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
                    .customizationID("title")
                }

                if showColRTT || showColTTL {
                    TableColumn(rttTtlHeader) { host in
                        Text(rttTtlCell(host))
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .help(ttlHint(for: host.ttl))
                    }
                    .width(min: 60, ideal: 90, max: 140)
                    .customizationID("rttTtl")
                }

                if showColPorts {
                    TableColumn("Ports") { host in
                        Text(PortScanner.formatList(host.openPorts))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 140)
                    .customizationID("ports")
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


}
