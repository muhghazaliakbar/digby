import SwiftUI

struct AnalyzeView: View {
    @Bindable var model: AnalyzeModel

    var body: some View {
        VStack(spacing: 12) {
            breadcrumb
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x0B0C0F))
                    if model.isLoading {
                        TreemapSkeleton()
                    } else if model.failed.contains(model.currentPath) {
                        VStack(spacing: 10) {
                            Text("Could not read this folder").font(Fonts.ui(14, .semibold))
                            LinkButton(title: "Try again", action: model.rescan)
                        }
                    } else {
                        TreemapView(model: model)
                            .id(model.changes)
                            .modifier(ZoomEnter(direction: model.direction, origin: model.origin))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                SidePanel(model: model).frame(width: 300)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .pageEnter()
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            UpButton(enabled: !model.stack.isEmpty, action: model.up)
                .padding(.trailing, 6)
            ForEach(Array(model.crumbs.enumerated()), id: \.offset) { index, crumb in
                HStack(spacing: 4) {
                    if index > 0 { Text("/").font(Fonts.ui(14)).foregroundStyle(DS.borderMuted) }
                    CrumbButton(title: crumb.name, current: index == model.crumbs.count - 1) { model.go(to: index) }
                }
                .slideIn(0.35)
            }
            Spacer()
            if !model.isLoading {
                CountingText(value: model.total) { Fmt.size($0) }
                    .counting(model.total, duration: 0.7)
                    .font(Fonts.mono(13))
                    .foregroundStyle(DS.textMuted)
            }
        }
        .frame(minHeight: 32)
    }
}

private struct UpButton: View {
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("‹")
                .font(.system(size: 15))
                .foregroundStyle(hovering ? DS.textPrimary : DS.textSecondary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(DS.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hovering ? DS.borderMuted : DS.border, lineWidth: 1))
                .offset(x: hovering && enabled ? -2 : 0)
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .help("Up one level")
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
    }
}

private struct CrumbButton: View {
    let title: String
    let current: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fonts.ui(14))
                .foregroundStyle(current ? DS.textPrimary : DS.textMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? DS.surfaceRaised : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Zoom into the clicked tile (scale .4 → 1 from its center) or out (1.5 → 1).
private struct ZoomEnter: ViewModifier {
    let direction: AnalyzeModel.Direction
    let origin: UnitPoint
    @State private var shown = false

    func body(content: Content) -> some View {
        let from: CGFloat = direction == .into ? 0.4 : direction == .out ? 1.5 : 1
        content
            .scaleEffect(shown || Motion.reduce ? 1 : from, anchor: origin)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(Motion.easeOut(0.5)) { shown = true } }
    }
}

private struct TreemapView: View {
    @Bindable var model: AnalyzeModel

    var body: some View {
        GeometryReader { geo in
            let kids = Array(model.children.prefix(80))
            let tiles = Treemap.layout(kids.enumerated().map { ($0, $1.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(tiles.filter { min($0.rect.width, $0.rect.height) >= 6 }.map { PlacedTile(index: $0.item, node: kids[$0.item], rect: $0.rect) }) { tile in
                    let node = tile.node
                    let color = DS.palette[tile.index % DS.palette.count]
                    TreemapTile(node: node, color: color, size: tile.rect.size, selected: model.selected == node.path) {
                        if node.isDir {
                            let r = tile.rect
                            model.drill(node, origin: UnitPoint(x: r.midX / max(geo.size.width, 1), y: r.midY / max(geo.size.height, 1)))
                        } else {
                            withAnimation(.easeOut(duration: 0.25)) { model.selected = node.path }
                        }
                    }
                    .frame(width: tile.rect.width, height: tile.rect.height)
                    .offset(x: tile.rect.minX, y: tile.rect.minY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .overlay {
                if kids.isEmpty {
                    Text("This folder is empty").font(Fonts.ui(13.5)).foregroundStyle(DS.textFaint)
                }
            }
        }
    }
}

private struct PlacedTile: Identifiable {
    var id: String { node.path }
    let index: Int
    let node: AnalyzeModel.Node
    let rect: CGRect
}

private struct TreemapTile: View {
    let node: AnalyzeModel.Node
    let color: Color
    let size: CGSize
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if size.width > 64 && size.height > 30 {
                Text(node.name).font(Fonts.ui(13.5, .semibold)).lineLimit(1)
            }
            if size.width > 64 && size.height > 50 {
                Text(Fmt.size(node.size)).font(Fonts.mono(12)).foregroundStyle(DS.textSecondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(selected ? 0.33 : 0.17)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(selected ? 1 : 0.31), lineWidth: 1))
        .shadow(color: selected ? color : .clear, radius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .brightness(hovering ? 0.12 : 0)
        .scaleEffect(hovering ? 0.985 : 1)
        .animation(Motion.overshoot(0.25, 1.5), value: hovering)
        .padding(2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .help("\(node.name) · \(Fmt.size(node.size))\(node.isDir ? " · click to open" : "")")
    }
}

private struct TreemapSkeleton: View {
    var body: some View {
        GeometryReader { geo in
            let tiles = Treemap.layout([40.0, 22, 14, 9, 6, 4, 3, 2].enumerated().map { ($0, $1) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.surface)
                        .overlay(Shimmer(period: 1.4, color: .white.opacity(0.04)))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(2)
                        .frame(width: tile.rect.width, height: tile.rect.height)
                        .offset(x: tile.rect.minX, y: tile.rect.minY)
                }
            }
        }
        .overlay {
            HStack(spacing: 10) {
                Spinner()
                Text("Measuring folders…").font(Fonts.ui(13)).foregroundStyle(DS.textMuted)
            }
        }
        .fadeIn()
    }
}

private struct SidePanel: View {
    @Bindable var model: AnalyzeModel

    var body: some View {
        let kids = model.children
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.stack.isEmpty ? "Home folder" : URL(fileURLWithPath: model.currentPath).lastPathComponent)
                    .font(Fonts.ui(15, .semibold))
                    .lineLimit(1)
                Text(model.isLoading ? "Scanning…" : "\(kids.count) items · click a block to open it")
                    .font(Fonts.ui(12.5))
                    .foregroundStyle(DS.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.borderSubtle2).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(kids.enumerated()), id: \.element.path) { index, node in
                        SideRow(model: model, node: node, color: DS.palette[index % DS.palette.count],
                                fraction: node.size / max(kids.first?.size ?? 1, 1))
                    }
                }
                .padding(6)
            }
            .id(model.changes)
            .slideIn(0.4)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(DS.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.border, lineWidth: 1))
    }
}

private struct SideRow: View {
    @Bindable var model: AnalyzeModel
    let node: AnalyzeModel.Node
    let color: Color
    let fraction: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                Text(node.name).font(Fonts.ui(13.5)).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                Text(Fmt.size(node.size)).font(Fonts.mono(12)).foregroundStyle(DS.textMuted).fixedSize()
                if node.isDir {
                    IconButton(nudge: 2, help: "Open folder", action: { model.drill(node) }) {
                        Text("›").font(.system(size: 15))
                    }
                }
                IconButton(hoverBackground: Color(hex: 0x2A1A1C), hoverForeground: DS.danger, foreground: DS.textFaint, help: "Move to Trash", action: { model.trash(node) }) {
                    StrokeIcon(data: "M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13", size: 14, lineWidth: 1.8)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    DS.borderSubtle2
                    color.frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 3)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(model.selected == node.path ? Color(hex: 0x1C2433) : .clear))
        .contentShape(Rectangle())
        .hoverBackground(.clear, DS.surfaceRaised, radius: 9)
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { model.selected = node.path } }
        .help(node.path)
    }
}
