import SwiftUI
import AppKit

struct HostInspector: View {
    let host: Host?
    let label: String?
    let anchor: String?
    let services: [MDNSDiscovery.ServiceRecord]
    let onLabelChange: (String?) -> Void

    @State private var labelText: String = ""
    @State private var labelSavedAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let host {
                    hostSections(host)
                } else {
                    placeholder
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            labelText = label ?? ""
        }
        .onDisappear {
            commitLabelIfChanged()
        }
        .onChange(of: host?.id) { _, _ in
            commitLabelIfChanged()
            labelText = label ?? ""
        }
    }

    @ViewBuilder
    private func hostSections(_ host: Host) -> some View {
        header(host: host)
        Divider()
        labelSection(host: host)
        Divider()
        infoSection(host: host)
        if !services.isEmpty {
            Divider()
            servicesSection
        }
        Divider()
        PingMonitorView(ip: host.ip)
        Divider()
        actionsSection(host: host)
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 60)
            Image(systemName: "rectangle.righthalf.inset.filled")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Select a host")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click a row to view its details.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func commitLabelIfChanged() {
        guard host != nil else { return }
        let trimmed = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (label ?? "") {
            onLabelChange(trimmed.isEmpty ? nil : trimmed)
            labelSavedAt = Date()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                if let saved = labelSavedAt, Date().timeIntervalSince(saved) >= 1.4 {
                    labelSavedAt = nil
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func header(host: Host) -> some View {
        let kind = DeviceClassifier.classify(host)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.sfSymbol)
                .font(.system(size: 32))
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(host.ip).font(.title3).fontWeight(.medium).monospaced()
                    .textSelection(.enabled)
                if let v = host.vendor {
                    Text(v).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if kind != .unknown {
                    Text(kind.label).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func labelSection(host: Host) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Label").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if labelSavedAt != nil {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            TextField("Add label…  (e.g. NAS  #server)", text: $labelText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitLabelIfChanged() }
            Text("Press Enter to save · #tag is searchable")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func infoSection(host: Host) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow("Hostname", host.hostname)
            if let nb = host.netbiosName {
                infoRow("NetBIOS", nb)
            }
            if let wg = host.workgroup {
                infoRow("Workgroup", wg)
            }
            infoRow("MAC", host.mac?.uppercased(), monospaced: true)
            if let anchor {
                infoRow("Anchor", anchor, monospaced: true, secondary: true)
            }
            if !host.openPorts.isEmpty {
                infoRow("Ports", PortScanner.formatList(host.openPorts))
            }
            if let t = host.serviceTitle {
                infoRow("Title", t)
            }
            if let rtt = host.rttMs {
                infoRow("RTT (initial)", String(format: "%.1f ms", rtt), monospaced: true)
            }
            if let ttl = host.ttl {
                infoRow("TTL", String(ttl), monospaced: true)
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ key: String, _ value: String?, monospaced: Bool = false, secondary: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Group {
                if let v = value, !v.isEmpty {
                    Text(v)
                        .textSelection(.enabled)
                        .lineLimit(3)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .font(secondary ? .caption : .callout)
            .monospaced(monospaced)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Services (mDNS)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(services.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(services, id: \.self) { svc in
                    HStack(spacing: 6) {
                        Text(svc.displayType)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(.tint)
                            .clipShape(Capsule())
                        Text(svc.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionsSection(host: Host) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            actionGroup("Connect") {
                Button { HostActions.openBrowser(ip: host.ip) } label: {
                    Label("HTTP", systemImage: "safari")
                }
                Button { HostActions.openBrowser(ip: host.ip, scheme: "https") } label: {
                    Label("HTTPS", systemImage: "lock.shield")
                }
                Button { HostActions.openSSH(ip: host.ip) } label: {
                    Label("SSH", systemImage: "terminal")
                }
                Button { HostActions.openVNC(ip: host.ip) } label: {
                    Label("VNC", systemImage: "rectangle.connected.to.line.below")
                }
                Button { HostActions.openRDP(ip: host.ip) } label: {
                    Label("RDP", systemImage: "display")
                }
                Button { HostActions.openSMB(ip: host.ip) } label: {
                    Label("SMB", systemImage: "externaldrive.connected.to.line.below")
                }
                Button { HostActions.openAFP(ip: host.ip) } label: {
                    Label("AFP", systemImage: "externaldrive")
                }
                Button { HostActions.openTelnet(ip: host.ip) } label: {
                    Label("Telnet", systemImage: "terminal.fill")
                }
            }

            actionGroup("Tools") {
                Button { HostActions.pingInTerminal(ip: host.ip) } label: {
                    Label("Ping", systemImage: "wave.3.right")
                }
                if let mac = host.mac {
                    Button {
                        Task { await HostActions.wakeOnLAN(mac: mac) }
                    } label: {
                        Label("Wake", systemImage: "power.circle.fill")
                    }
                }
            }

            actionGroup("Copy") {
                Button { HostActions.copy(host.ip) } label: {
                    Label("IP", systemImage: "doc.on.doc")
                }
                if let hostname = host.hostname {
                    Button { HostActions.copy(hostname) } label: {
                        Label("Hostname", systemImage: "doc.on.doc")
                    }
                }
                if let mac = host.mac {
                    Button { HostActions.copy(mac.uppercased()) } label: {
                        Label("MAC", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 60), spacing: 6),
                    GridItem(.flexible(minimum: 60), spacing: 6),
                    GridItem(.flexible(minimum: 60), spacing: 6)
                ],
                spacing: 6
            ) {
                content()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Ping monitor isolated child view

/// Isolated subview that owns the PingMonitor. When samples update every second,
/// only this view re-renders — not the entire HostInspector — preventing AppKit
/// constraint loops in the inspector column.
struct PingMonitorView: View {
    let ip: String
    @State private var monitor = PingMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ping (live)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let rtt = monitor.lastRTT {
                    Text(String(format: "%.1f ms", rtt))
                        .font(.callout).monospacedDigit()
                        .foregroundStyle(.green)
                } else if !monitor.samples.isEmpty {
                    Text("no response")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else {
                    Text("…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            PingSparkline(samples: monitor.samples)
                .frame(height: 56)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 14) {
                if let avg = monitor.avgRTT {
                    Text("avg \(String(format: "%.1f", avg))")
                        .monospacedDigit()
                }
                if let lo = monitor.minRTT, let hi = monitor.maxRTT {
                    Text("min \(String(format: "%.1f", lo)) · max \(String(format: "%.1f", hi))")
                        .monospacedDigit()
                }
                Spacer()
                Text("loss \(Int(monitor.lossRate * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(monitor.lossRate > 0 ? .red : .secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            monitor.start(ip: ip)
        }
        .onDisappear {
            monitor.stop()
        }
        .onChange(of: ip) { _, newIP in
            monitor.start(ip: newIP)
        }
    }
}

struct PingSparkline: View {
    let samples: [Double?]

    var body: some View {
        Canvas { ctx, size in
            guard samples.count >= 2 else { return }
            let alive = samples.compactMap { $0 }
            guard !alive.isEmpty else { return }

            let maxV = alive.max() ?? 1
            let minV = alive.min() ?? 0
            let range = max(maxV - minV, 1)

            let topPad: CGFloat = 4
            let bottomPad: CGFloat = 4
            let h = max(size.height - topPad - bottomPad, 1)
            let w = max(size.width - 8, 1)
            let stepX = w / CGFloat(max(samples.count - 1, 1))

            var path = Path()
            var movedTo = false
            for (i, sample) in samples.enumerated() {
                let x = 4 + CGFloat(i) * stepX
                if let v = sample {
                    let y = topPad + (h - CGFloat(v - minV) / CGFloat(range) * h)
                    if !movedTo {
                        path.move(to: .init(x: x, y: y))
                        movedTo = true
                    } else {
                        path.addLine(to: .init(x: x, y: y))
                    }
                } else {
                    ctx.fill(
                        Path(ellipseIn: .init(x: x - 1.5, y: size.height - 4, width: 3, height: 3)),
                        with: .color(.red)
                    )
                    movedTo = false
                }
            }
            ctx.stroke(path, with: .color(.green), lineWidth: 1.5)
        }
    }
}
