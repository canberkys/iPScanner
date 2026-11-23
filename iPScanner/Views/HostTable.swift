import SwiftUI

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
                            .help(DeviceClassifier.assessment(host).evidence)
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

                if showColRTT || showColTTL {
                    TableColumn(rttTtlHeader) { host in
                        Text(rttTtlCell(host))
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .help(ttlHint(for: host.ttl))
                    }
                    .width(min: 60, ideal: 90, max: 140)
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
            // Edit › Copy (⌘C) copies selected IPs only while the table has focus;
            // text fields keep their normal copy behavior.
            .onCopyCommand { selectedIPsForCopy() }
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
