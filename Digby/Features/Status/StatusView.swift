import SwiftUI

struct StatusView: View {
    @Environment(AppModel.self) private var app
    let model: StatusModel

    var body: some View {
        GeometryReader { geo in
            let mw = geo.size.width
            let health = mw < 1000 ? 12 : 4
            let wide = mw < 1000 ? 12 : 8
            let small = mw < 1000 ? (mw < 640 ? 12 : 6) : 4
            ScrollView {
                SpanGrid(columns: 12, spacing: 14) {
                    HealthCard(model: model).span(health).rise(0)
                    CPUCard(model: model).span(wide).rise(0.06)
                    MemoryCard(model: model).span(small).rise(0.12)
                    DiskCard().span(small).rise(0.18)
                    NetworkCard(model: model).span(small).rise(0.24)
                    ProcessesCard(model: model).span(wide).rise(0.3)
                    BatteryCard(model: model).span(small).rise(0.36)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .pageEnter()
    }
}

// MARK: - Cards

private struct HealthCard: View {
    @Environment(AppModel.self) private var app
    let model: StatusModel
    @State private var reveal: Double = 0

    var body: some View {
        SpotCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    ZStack {
                        SegmentedRing(segments: [RingSegment(id: "h", fraction: Double(model.healthScore) / 100 * reveal,
                                                             color: model.healthScore >= 70 ? DS.success : DS.warning)],
                                      track: DS.borderSubtle2, thickness: 9, tickEvery: 9, tickWidth: 1.5, tickColor: DS.surface)
                        CountingText(value: Double(model.healthScore) * reveal) { "\(Int($0.rounded()))" }
                            .font(Fonts.mono(28, .medium))
                    }
                    .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Health").cardLabel()
                        Text(model.loaded ? model.healthLabel : "Measuring…").font(Fonts.ui(24, .semibold))
                        Text(subtitle).font(Fonts.ui(13)).foregroundStyle(DS.textMuted)
                    }
                }
                VStack(spacing: 6) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                        SuggestionRow(text: s.text, cmd: s.cmd, color: s.color) { withAnimation(Motion.nav) { app.go(s.module) } }
                            .rise(0.25 + Double(i) * 0.07)
                    }
                }
            }
        }
        .onAppear { withAnimation(Motion.count(1.2)) { reveal = 1 } }
        .onChange(of: model.loaded) { reveal = 0; withAnimation(Motion.count(1.2)) { reveal = 1 } }
    }

    private var subtitle: String {
        [model.uptime.isEmpty ? nil : "Up \(model.uptime)", model.osVersion.isEmpty ? nil : model.osVersion]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var suggestions: [(text: String, cmd: String, color: Color, module: Module)] {
        let clean = app.clean, opt = app.optimize, purge = app.purge
        return [
            clean.phase == .done && !clean.lastDry
                ? ("Cleaned \(Fmt.size(clean.freed)) this session", "mo clean", DS.success, .clean)
                : ("Scan for caches and leftovers", "mo clean", DS.accent, .clean),
            opt.phase == .done
                ? ("Maintenance tasks finished", "mo optimize", DS.success, .optimize)
                : ("\(opt.tasks.count) maintenance tasks ready", "mo optimize", DS.violet, .optimize),
            !purge.scanned
                ? ("Find old build artifacts in your projects", "mo purge", DS.warning, .purge)
                : purge.reclaimable > 10_000_000
                ? ("\(Fmt.size(purge.reclaimable)) of build artifacts in your projects", "mo purge", DS.warning, .purge)
                : ("Project artifacts cleared", "mo purge", DS.success, .purge),
        ]
    }
}

private struct SuggestionRow: View {
    let text: String
    let cmd: String
    let color: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 7, height: 7).shadow(color: color, radius: 4)
                Text(text).font(Fonts.ui(13.5)).foregroundStyle(DS.textPrimary).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                Text(cmd).font(Fonts.mono(11.5)).foregroundStyle(DS.textFaint).fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Color(hex: 0x20252C) : DS.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(hovering ? DS.borderHover : Color(hex: 0x242931), lineWidth: 1))
            .offset(x: hovering ? 3 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .onHover { h in withAnimation(Motion.easeOut(0.2)) { hovering = h } }
    }
}

private struct CPUCard: View {
    let model: StatusModel

    var body: some View {
        SpotCard(glowOpacity: 0.08, glowRadius: 420) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("CPU").cardLabel()
                            LiveDot()
                            Text("live").font(Fonts.ui(10.5, .semibold)).tracking(0.6).textCase(.uppercase).foregroundStyle(DS.success)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(Int(model.cpuUsage.rounded()))%").font(Fonts.mono(30, .medium)).contentTransition(.numericText())
                            Text(detail).font(Fonts.ui(13)).foregroundStyle(DS.textMuted).lineLimit(1)
                        }
                    }
                    .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 14) {
                        legend("Performance", DS.accent)
                        legend("Efficiency", DS.violet)
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    HStack(spacing: 5) {
                        ForEach(Array(cores.enumerated()), id: \.offset) { i, core in
                            CoreBar(value: core.value, color: core.p ? DS.accent : DS.violet, top: core.p ? DS.accentLight : Color(hex: 0xA99DFF), label: core.label)
                                .rise(0.2 + Double(i) * 0.03)
                                .help("\(core.p ? "P" : "E")-core \(core.label.dropFirst()): \(Int(core.value))%")
                        }
                    }
                    .fixedSize()
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(DS.sparkBg)
                            Sparkline(values: model.cpuHistory, maxValue: 100, closed: true).fill(DS.accent.opacity(0.14))
                            Sparkline(values: model.cpuHistory, maxValue: 100).stroke(DS.accent, lineWidth: 1.5)
                        }
                        .frame(height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        HStack {
                            Text("48s ago")
                            Spacer()
                            Text("now")
                        }
                        .font(Fonts.mono(10.5))
                        .foregroundStyle(DS.textFaint)
                    }
                }
            }
        }
    }

    private var detail: String {
        var parts = [model.cpuModel.isEmpty ? nil : model.cpuModel]
        if !model.pCores.isEmpty || !model.eCores.isEmpty {
            parts.append("\(model.pCores.count)P + \(model.eCores.count)E cores")
        }
        if model.cpuTemp > 0 { parts.append("\(Int(model.cpuTemp))°C") }
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private var cores: [(value: Double, p: Bool, label: String)] {
        let p = model.pCores.enumerated().map { (value: $1, p: true, label: "P\($0 + 1)") }
        let e = model.eCores.enumerated().map { (value: $1, p: false, label: "E\($0 + 1)") }
        return Array((p + e).prefix(16))
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title)
        }
        .font(Fonts.ui(12))
        .foregroundStyle(DS.textMuted)
    }
}

private struct CoreBar: View {
    let value: Double
    let color: Color
    let top: Color
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4).fill(DS.surfaceTrack)
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [color, top], startPoint: .bottom, endPoint: .top))
                    .frame(height: 104 * min(max(value, 0), 100) / 100)
            }
            .frame(width: 14, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label).font(Fonts.mono(9.5)).foregroundStyle(DS.textFaint)
        }
    }
}

private struct MemoryCard: View {
    let model: StatusModel

    var body: some View {
        SpotCard(glowRadius: 360) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory").cardLabel()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(gb(model.memUsed)).font(Fonts.mono(26, .medium)).contentTransition(.numericText())
                        Text("of \(Int((model.memTotal / 1_073_741_824).rounded())) GB · pressure \(model.pressure)")
                            .font(Fonts.ui(13)).foregroundStyle(DS.textMuted).lineLimit(1)
                    }
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    HStack(spacing: 2) {
                        ForEach(segments, id: \.0) { seg in
                            Rectangle().fill(seg.2).frame(width: max(0, w * seg.1 / max(model.memTotal, 1) - 2))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 10)
                .background(DS.surfaceTrack)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        legend(segments[0])
                        legend(segments[1])
                    }
                    GridRow {
                        legend(segments[2])
                        legend(("Swap", model.swapUsed, DS.borderStrong))
                    }
                }
            }
        }
    }

    private var segments: [(String, Double, Color)] {
        [("App", model.memApp, DS.accent), ("Wired", model.memWired, DS.violet), ("Compressed", model.memCompressed, DS.cyan)]
    }

    private func gb(_ bytes: Double) -> String { String(format: "%.1f GB", bytes / 1_073_741_824) }

    private func legend(_ seg: (String, Double, Color)) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(seg.2).frame(width: 8, height: 8)
            Text(seg.0).foregroundStyle(DS.textMuted).frame(maxWidth: .infinity, alignment: .leading)
            Text(gb(seg.1)).font(Fonts.mono(12.5)).foregroundStyle(DS.textPrimary).contentTransition(.numericText())
        }
        .font(Fonts.ui(12.5))
    }
}

private struct DiskCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let disk = app.disk
        SpotCard(glowRadius: 360) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disk").cardLabel()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        CountingText(value: disk.free) { Fmt.size($0) }
                            .counting(disk.free, duration: 1.1)
                            .font(Fonts.mono(26, .medium))
                            .foregroundStyle(disk.tweening ? DS.success : DS.textPrimary)
                        Text("free · APFS").font(Fonts.ui(13)).foregroundStyle(DS.textMuted)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        DS.surfaceTrack
                        Rectangle().fill(disk.usedFraction > 0.85 ? DS.warning : DS.accent)
                            .frame(width: geo.size.width * disk.usedFraction)
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                HStack {
                    (Text("Read ") + Text(rate(app.status.diskRead)).font(Fonts.mono(12.5)).foregroundColor(DS.textPrimary))
                    Spacer()
                    (Text("Write ") + Text(rate(app.status.diskWrite)).font(Fonts.mono(12.5)).foregroundColor(DS.textPrimary))
                }
                .font(Fonts.ui(12.5))
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
                Spacer(minLength: 0)
                LinkButton(title: "See what is using space →", nudge: 3) { withAnimation(Motion.nav) { app.go(.analyze) } }
            }
        }
    }

    private func rate(_ v: Double) -> String { "\(Int(v.rounded())) MB/s" }
}

private struct NetworkCard: View {
    let model: StatusModel

    var body: some View {
        let maxValue = max(0.01, (model.netDown + model.netUp).max() ?? 0) * 1.15
        SpotCard(glowRadius: 360) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Network · \(model.interfaceName)").cardLabel()
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Down").font(Fonts.ui(12)).foregroundStyle(DS.textMuted)
                        Text(Fmt.rate(model.netDown.last ?? 0)).font(Fonts.mono(18)).foregroundStyle(DS.accent).contentTransition(.numericText())
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Up").font(Fonts.ui(12)).foregroundStyle(DS.textMuted)
                        Text(Fmt.rate(model.netUp.last ?? 0)).font(Fonts.mono(18)).foregroundStyle(DS.success).contentTransition(.numericText())
                    }
                }
                ZStack {
                    Sparkline(values: model.netDown, maxValue: maxValue, closed: true).fill(DS.accent.opacity(0.12))
                    Sparkline(values: model.netDown, maxValue: maxValue).stroke(DS.accent, lineWidth: 1.5)
                    Sparkline(values: model.netUp, maxValue: maxValue).stroke(DS.success, lineWidth: 1.5)
                }
                .frame(height: 56)
            }
        }
    }
}

private struct ProcessesCard: View {
    let model: StatusModel

    var body: some View {
        SpotCard(glowOpacity: 0.08, glowRadius: 420) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    Text("Top processes").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU").frame(width: 120, alignment: .leading)
                    Text("Memory").frame(width: 70, alignment: .trailing)
                }
                .cardLabel()
                ZStack(alignment: .top) {
                    ForEach(model.procs) { proc in
                        let rank = model.rank(of: proc)
                        ProcessRow(proc: proc, rank: rank)
                            .offset(y: CGFloat(rank) * 28)
                            .opacity(rank < 6 ? 1 : 0)
                            .animation(Motion.overshoot(0.7, 1.2), value: rank)
                    }
                }
                .frame(height: 168, alignment: .top)
                .clipped()
            }
        }
    }
}

private struct ProcessRow: View {
    let proc: StatusModel.Proc
    let rank: Int

    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank + 1)").font(Fonts.mono(11)).foregroundStyle(DS.textFaint).frame(width: 20, alignment: .leading)
            Text(proc.id).font(Fonts.ui(13.5)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        DS.surfaceTrack
                        DS.accent.frame(width: geo.size.width * min(max(proc.cpu * 2, 2), 100) / 100)
                    }
                }
                .frame(width: 60, height: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                Text(String(format: "%.1f%%", proc.cpu)).font(Fonts.mono(12)).foregroundStyle(DS.textSecondary).contentTransition(.numericText())
            }
            .frame(width: 120, alignment: .leading)
            Text(Fmt.size(proc.memory)).font(Fonts.mono(12)).foregroundStyle(DS.textMuted).contentTransition(.numericText()).frame(width: 70, alignment: .trailing)
        }
        .frame(height: 28)
    }
}

private struct BatteryCard: View {
    let model: StatusModel

    var body: some View {
        SpotCard(glow: DS.success, glowOpacity: 0.08, glowRadius: 360) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery").cardLabel()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model.battery.map { "\(Int($0.percent))%" } ?? "AC").font(Fonts.mono(26, .medium))
                        Text(statusText).font(Fonts.ui(13)).foregroundStyle(charging ? DS.success : DS.textMuted).lineLimit(1)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        DS.surfaceTrack
                        ZStack {
                            DS.success
                            if charging { Shimmer(period: 2) }
                        }
                        .frame(width: geo.size.width * (model.battery?.percent ?? 100) / 100)
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    row("Max capacity", model.battery?.capacity.map { "\(Int($0))%" } ?? "—")
                    row("Cycle count", model.battery?.cycles.map { "\($0)" } ?? "—")
                    row("Temperature", model.battery?.temperature.flatMap { $0 > 0 ? "\(Int($0))°C" : nil } ?? "—")
                }
            }
        }
    }

    private var charging: Bool { model.battery?.status.lowercased().contains("charg") == true && model.battery?.status.lowercased() != "discharging" }

    private var statusText: String {
        guard let b = model.battery else { return "No battery" }
        switch b.status.lowercased() {
        case "charging": return (b.watts ?? 0) > 0 ? "Charging · \(Int(b.watts!)) W" : "Charging"
        case "charged", "full": return "Charged"
        case "discharging": return b.timeLeft.map { "On battery · \($0) left" } ?? "On battery"
        default: return b.status.capitalized
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).font(Fonts.ui(12.5)).foregroundStyle(DS.textMuted).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(Fonts.mono(12.5)).foregroundStyle(DS.textPrimary)
        }
    }
}

// MARK: - 12-column grid

nonisolated private struct SpanKey: LayoutValueKey { static let defaultValue = 12 }

extension View {
    func span(_ columns: Int) -> some View { layoutValue(key: SpanKey.self, value: columns) }
}

/// CSS-grid-like layout: items span N of `columns`, rows stretch to their tallest item.
nonisolated struct SpanGrid: Layout {
    var columns = 12
    var spacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        let rows = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        let unit = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        for row in arrange(width: bounds.width, subviews: subviews) {
            var col = 0
            for i in row.items {
                let span = min(subviews[i][SpanKey.self], columns)
                let w = unit * CGFloat(span) + spacing * CGFloat(span - 1)
                subviews[i].place(at: CGPoint(x: bounds.minX + CGFloat(col) * (unit + spacing), y: y),
                                  proposal: ProposedViewSize(width: w, height: row.height))
                col += span
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        let unit = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var rows: [Row] = []
        var row = Row()
        var used = 0
        for (i, view) in subviews.enumerated() {
            let span = min(view[SpanKey.self], columns)
            if used + span > columns {
                rows.append(row)
                row = Row()
                used = 0
            }
            let w = unit * CGFloat(span) + spacing * CGFloat(span - 1)
            row.height = max(row.height, view.sizeThatFits(ProposedViewSize(width: w, height: nil)).height)
            row.items.append(i)
            used += span
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
