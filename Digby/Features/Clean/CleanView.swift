import SwiftUI

struct CleanView: View {
    @Bindable var model: CleanModel

    var body: some View {
        Group {
            if model.phase == .results {
                CleanResultsView(model: model).id("results").pageEnter()
            } else {
                CleanCenteredView(model: model).id("centered").pageEnter(0.5)
            }
        }
    }
}

// MARK: - Idle / scanning / cleaning / done

private struct CleanCenteredView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: CleanModel

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 28) {
                    ring
                    text
                    buttons
                    chips
                }
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollIndicators(.never)
        }
    }

    private var phase: CleanModel.Phase { model.phase }
    private var busy: Bool { phase == .scanning || phase == .cleaning }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            if phase == .idle { BreathingHalo().padding(-16) }
            if busy { CometGlow(hex: phase == .cleaning ? 0x3DDC97 : 0x3D8BFF).padding(-12) }
            SegmentedRing(segments: segments, track: DS.surfaceTrack, thickness: 26)
            RingCenter(inset: 26) {
                VStack(spacing: 4) {
                    if showCheck { DrawnCheck().padding(.bottom, 2) }
                    CountingText(value: ringValue) { Fmt.size($0) }
                        .counting(ringValue, duration: phase == .done ? 1.0 : 0.35)
                        .font(Fonts.mono(40, .medium))
                        .tracking(-1.5)
                        .foregroundStyle(DS.textPrimary)
                    Text(ringLabel).font(Fonts.ui(13)).foregroundStyle(DS.textMuted)
                }
            }
            if busy { OrbitDot(hex: phase == .cleaning ? 0x3DDC97 : 0x3D8BFF) }
            if phase == .done && !model.lastDry { ParticleBurst(id: model.burstID) }
        }
        .frame(width: 300, height: 300)
    }

    private var segments: [RingSegment] {
        switch phase {
        case .idle: []
        case .scanning: [RingSegment(id: "p", fraction: model.progress, color: DS.accent)]
        case .cleaning: [RingSegment(id: "p", fraction: model.progress, color: DS.success)]
        case .done: [RingSegment(id: "p", fraction: model.progress, color: model.lastDry ? DS.accent : DS.success)]
        case .empty: [RingSegment(id: "p", fraction: 1, color: DS.success)]
        case .results: []
        }
    }

    private var ringValue: Double {
        switch phase {
        case .idle: app.disk.free
        case .scanning: model.foundBytes
        case .cleaning, .done: model.freed
        default: 0
        }
    }

    private var ringLabel: String {
        switch phase {
        case .idle: "free on \(app.disk.volumeName)"
        case .scanning, .empty: "junk found"
        case .cleaning: model.dryRun ? "would be freed" : "freed"
        case .done: model.lastDry ? "could be freed" : "freed"
        case .results: ""
        }
    }

    private var showCheck: Bool { (phase == .done && !model.lastDry) || phase == .empty }

    // MARK: Text

    private var text: some View {
        VStack(spacing: 8) {
            Text(headline)
                .font(Fonts.ui(28, .semibold))
                .tracking(-0.4)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            if !subline.isEmpty {
                Text(subline)
                    .font(Fonts.ui(14.5))
                    .foregroundStyle(DS.textMuted)
                    .lineSpacing(14.5 * 0.5 - 4)
                    .multilineTextAlignment(.center)
            }
            if busy {
                Text(Fmt.tildePath(model.currentPath))
                    .font(Fonts.mono(12.5))
                    .foregroundStyle(DS.textFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
            }
        }
        .frame(maxWidth: 540)
    }

    private var headline: String {
        switch phase {
        case .idle: "Dig out the junk"
        case .scanning: "Scanning… \(Int(model.progress * 100))%"
        case .cleaning: "\(model.dryRun ? "Simulating" : "Cleaning")… \(Int(model.progress * 100))%"
        case .done: model.lastDry ? "Dry run finished" : "Your Mac is lighter"
        case .empty: "Nothing left to clean"
        case .results: ""
        }
    }

    private var subline: String {
        switch phase {
        case .idle: "Digby looks through caches, logs, developer leftovers and data from apps you already deleted. Nothing is removed until you review it."
        case .done:
            model.lastDry
                ? "No files were touched. Go back, switch off dry run, and clean for real."
                : "\(Fmt.grouped(model.freedItems)) items removed. \(Fmt.size(app.disk.free)) now free on \(app.disk.volumeName)."
        case .empty: "Caches and logs are already lean. Check back in a few weeks."
        default: ""
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: 10) {
            switch phase {
            case .idle:
                ScanButton(action: model.startScan)
            case .scanning:
                StopButton(action: model.cancel).pop(duration: 0.4)
            case .done, .empty:
                if phase == .done && model.lastDry {
                    Button("Back to results", action: model.backToResults)
                        .buttonStyle(PillButtonStyle(kind: .primary, height: 44, fontSize: 15, glow: false))
                        .rise(0.3)
                }
                Button("Scan again", action: model.startScan)
                    .buttonStyle(PillButtonStyle(kind: .secondary, height: 44, fontSize: 15))
                    .rise(0.4)
            default:
                EmptyView()
            }
        }
        .frame(minHeight: 48)
    }

    private var chips: some View {
        FlowLayout(spacing: 8) {
            ForEach(phase == .scanning ? model.chips : []) { chip in
                HStack(spacing: 8) {
                    Circle().fill(DS.palette[chip.colorIndex % 8]).frame(width: 7, height: 7)
                        .shadow(color: DS.palette[chip.colorIndex % 8], radius: 4)
                    Text(chip.name).font(Fonts.ui(13))
                    Text(Fmt.size(chip.bytes)).font(Fonts.mono(12)).foregroundStyle(DS.textMuted)
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(DS.surface))
                .overlay(Capsule().strokeBorder(DS.border, lineWidth: 1))
                .pop(duration: 0.45)
            }
        }
        .frame(maxWidth: 640, minHeight: 32)
    }
}

// MARK: - Results

private struct CleanResultsView: View {
    @Bindable var model: CleanModel
    @State private var reveal: Double = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if geo.size.width >= 860 {
                        ringColumn
                            .frame(width: min(max(geo.size.width * 0.26, 220), 280))
                            .overlay(alignment: .trailing) { Rectangle().fill(DS.borderSubtle).frame(width: 1) }
                    }
                    list
                }
                .frame(maxHeight: .infinity)
                footer.rise(0.15)
            }
        }
        .onAppear { withAnimation(Motion.count(1.0)) { reveal = 1 } }
    }

    private var ringColumn: some View {
        VStack(spacing: 24) {
            ZStack {
                SegmentedRing(segments: model.categories.map { cat in
                    RingSegment(id: cat.id, fraction: model.resultTotal > 0 ? model.selectedBytes(in: cat) / model.resultTotal * reveal : 0, color: cat.color)
                }, thickness: 20)
                .animation(Motion.easeOut(0.5), value: model.selected)
                RingCenter(inset: 20) {
                    VStack(spacing: 2) {
                        CountingText(value: model.selectedTotal) { Fmt.size($0) }
                            .counting(model.selectedTotal, duration: 0.7)
                            .font(Fonts.mono(32, .medium))
                            .tracking(-1)
                        Text("selected").font(Fonts.ui(12.5)).foregroundStyle(DS.textMuted)
                    }
                }
            }
            .frame(width: 228, height: 228)
            .pop(duration: 0.6)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Found").foregroundStyle(DS.textMuted)
                    Text(Fmt.size(model.resultTotal)).font(Fonts.mono(13)).foregroundStyle(DS.textPrimary).gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("Free after cleaning").foregroundStyle(DS.textMuted)
                    FreeAfter(model: model).gridColumnAlignment(.trailing)
                }
            }
            .font(Fonts.ui(13))
            .frame(maxWidth: .infinity)
            .rise(0.2)
        }
        .padding(28)
        .frame(maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text("Review before anything is removed. Expand a category to pick individual locations.")
                        .font(Fonts.ui(14))
                        .foregroundStyle(DS.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LinkButton(title: "Select all", action: model.selectAll)
                    LinkButton(title: "None", color: DS.textMuted, hoverColor: DS.textPrimary, action: model.selectNone)
                }
                Panel {
                    VStack(spacing: 0) {
                        ForEach(Array(model.categories.enumerated()), id: \.element.id) { index, cat in
                            CategoryRow(model: model, category: cat)
                                .rise(0.12 + Double(min(index, 14)) * 0.055)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            ToggleSwitch(isOn: model.dryRun) { model.dryRun.toggle() }
            VStack(alignment: .leading, spacing: 1) {
                Text("Dry run").font(Fonts.ui(13.5, .medium))
                Text("Preview only, nothing is deleted").font(Fonts.ui(12)).foregroundStyle(DS.textMuted)
            }
            Spacer()
            Text("\(model.selectedCount) of \(model.itemCount) locations").font(Fonts.ui(13)).foregroundStyle(DS.textMuted)
            Button(action: model.startClean) {
                HStack(spacing: 0) {
                    Text(model.dryRun ? "Preview " : "Clean ")
                    CountingText(value: model.selectedTotal) { Fmt.size($0) }.counting(model.selectedTotal, duration: 0.5)
                }
            }
            .buttonStyle(PillButtonStyle(kind: model.dryRun ? .muted : .primary, enabled: model.selectedTotal > 0))
            .disabled(model.selectedTotal <= 0)
            .animation(.easeOut(duration: 0.25), value: model.dryRun)
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
        .background(DS.bgFooter)
        .overlay(alignment: .top) { Rectangle().fill(DS.borderSubtle).frame(height: 1) }
    }
}

private struct FreeAfter: View {
    @Environment(AppModel.self) private var app
    let model: CleanModel

    var body: some View {
        let value = app.disk.free + model.selectedTotal
        CountingText(value: value) { Fmt.size($0) }
            .counting(value, duration: 0.7)
            .font(Fonts.mono(13))
            .foregroundStyle(DS.success)
    }
}

private struct CategoryRow: View {
    @Bindable var model: CleanModel
    let category: CleanModel.Category

    var body: some View {
        let open = model.openCategory == category.id
        let state = model.state(of: category)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { withAnimation(Motion.bouncy) { model.toggle(category) } } label: {
                    Checkbox(state: state)
                }
                .buttonStyle(PressStyle(scale: 0.8))

                RoundedRectangle(cornerRadius: 3).fill(category.color)
                    .frame(width: 10, height: 10)
                    .shadow(color: state == .none ? .clear : category.color.opacity(0.53), radius: 5)
                    .animation(.easeOut(duration: 0.3), value: state)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name).font(Fonts.ui(15, .semibold)).lineLimit(1)
                    Text(category.detail).font(Fonts.ui(13)).foregroundStyle(DS.textMuted).lineLimit(1)
                }
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

                (Text(Fmt.size(model.selectedBytes(in: category)))
                    + Text(" / \(Fmt.size(category.total))").foregroundColor(DS.textFaint))
                    .font(Fonts.mono(13.5))
                    .lineLimit(1)
                    .fixedSize()

                StrokeIcon(data: "M9 6l6 6-6 6", size: 14, lineWidth: 2)
                    .foregroundStyle(DS.textFaint)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .animation(Motion.overshoot(0.35, 1.5), value: open)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .hoverBackground(open ? DS.surfaceHover : .clear, DS.surfaceHover)
            .onTapGesture { model.toggleOpen(category) }

            if open {
                VStack(spacing: 0) {
                    ForEach(category.items) { item in
                        ItemRow(model: model, item: item)
                    }
                }
                .padding(.leading, 48)
                .padding(.trailing, 16)
                .padding(.bottom, 10)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: -8)),
                    removal: .opacity
                ))
            }
        }
        .clipped()
        .overlay(alignment: .bottom) { Rectangle().fill(DS.borderSubtle2).frame(height: 1) }
    }
}

private struct ItemRow: View {
    @Bindable var model: CleanModel
    let item: CleanModel.Item

    var body: some View {
        let on = model.selected.contains(item.id)
        HStack(spacing: 12) {
            Checkbox(state: on ? .all : .none, size: 16, dimmed: !item.excludable)
            Text(Fmt.tildePath(item.path))
                .font(Fonts.mono(12.5))
                .foregroundStyle(on ? DS.textSecondary : DS.textFaint)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.2), value: on)
            Text(Fmt.size(item.bytes)).font(Fonts.mono(12.5)).foregroundStyle(DS.textMuted).fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .contentShape(Rectangle())
        .hoverBackground(.clear, DS.surfaceRaised, radius: 7)
        .onTapGesture { withAnimation(Motion.bouncy) { model.toggle(item) } }
        .help(item.excludable ? item.path : "Mole cleans this location as a whole")
    }
}

// MARK: - Clean-specific effects

/// Primary idle "Scan" button with two looping ripple rings (2.4 s, offset 1.2 s).
private struct ScanButton: View {
    let action: () -> Void

    var body: some View {
        ZStack {
            RippleRings().frame(width: 128, height: 48)
            Button("Scan", action: action)
                .buttonStyle(PillButtonStyle(kind: .primary, height: 48, fontSize: 16, horizontal: 38, hoverScale: 1.03))
                .pop(0.15)
        }
    }

}

private struct StopButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("Stop")
                .font(Fonts.ui(14, .medium))
                .foregroundStyle(hovering ? DS.danger : DS.textSecondary)
                .padding(.horizontal, 22)
                .frame(height: 40)
                .overlay(Capsule().strokeBorder(hovering ? DS.danger : DS.borderStrong, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
    }
}

/// Check mark that pops in and draws itself.
private struct DrawnCheck: View {
    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().fill(DS.success.opacity(0.14)).frame(width: 31, height: 31)
            SVGPath(data: "M6.5 12.5l3.8 3.8L17.5 8.5")
                .trim(from: 0, to: drawn)
                .stroke(DS.success, style: StrokeStyle(lineWidth: 2.2 * 34 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 34, height: 34)
        }
        .frame(width: 34, height: 34)
        .pop(duration: 0.5)
        .onAppear { withAnimation(Motion.easeOut(0.55).delay(0.25)) { drawn = 1 } }
    }
}

/// ≈34 particles radiating from the ring after a real clean.
private struct ParticleBurst: View {
    let id: Int
    @State private var start = Date()
    @State private var particles: [Particle] = []

    struct Particle {
        var angle: Double
        var r1: Double
        var size: Double
        var color: Color
        var round: Bool
        var duration: Double
        var delay: Double
    }

    var body: some View {
        TimelineView(.animation(paused: Motion.reduce)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(start)
            Canvas { gc, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for p in particles {
                    let t = (elapsed - p.delay) / p.duration
                    guard t > 0, t < 1 else { continue }
                    let e = Self.ease(t)
                    let r = 128 + (p.r1 - 128) * e
                    let pos = CGPoint(x: c.x + cos(p.angle) * r, y: c.y + sin(p.angle) * r)
                    let scale = 0.3 + 0.7 * e
                    let alpha = t < 0.12 ? t / 0.12 : 1 - (t - 0.12) / 0.88
                    let s = p.size * scale
                    var g = gc
                    g.opacity = alpha
                    g.translateBy(x: pos.x, y: pos.y)
                    g.rotate(by: .degrees(260 * e))
                    let rect = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
                    g.fill(p.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2), with: .color(p.color))
                }
            }
        }
        .frame(width: 560, height: 560)
        .allowsHitTesting(false)
        .onAppear {
            start = Date()
            particles = (0..<34).map { i in
                Particle(angle: Double(i) / 34 * 2 * .pi + .random(in: -0.12...0.12),
                         r1: .random(in: 170...250),
                         size: .random(in: 4...9),
                         color: DS.palette[i % 6],
                         round: i % 3 != 0,
                         duration: .random(in: 0.8...1.3),
                         delay: .random(in: 0...0.15))
            }
        }
        .id(id)
    }

    /// cubic-bezier(.15,.7,.3,1) approximation.
    private static func ease(_ t: Double) -> Double { 1 - pow(1 - t, 3.2) }
}

/// Wrapping row layout for the category chips.
nonisolated struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.midX - row.width / 2
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width && !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
