import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var app
    @Namespace private var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Space for the window's traffic lights (repositioned to sit here, see WindowConfigurator).
            Color.clear.frame(height: 12).padding(.bottom, 20)

            logo.padding(.horizontal, 6).padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Module.groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.0)
                            .font(Fonts.ui(11, .semibold))
                            .tracking(0.88)
                            .textCase(.uppercase)
                            .foregroundStyle(DS.textFaint)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 6)
                        ForEach(group.1) { module in
                            NavItem(module: module, selected: app.view == module, namespace: highlight)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            DiskWidget()
        }
        .padding(.top, 16)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(width: DS.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(DS.bgSidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(DS.borderSubtle).frame(width: 1) }
    }

    private var logo: some View {
        HStack(spacing: 10) {
            Text("dg")
                .font(Fonts.mono(13, .semibold))
                .tracking(-0.5)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(DS.accent))
                .shadow(color: DS.accent.opacity(0.8), radius: 9, y: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text("Digby").font(Fonts.ui(16, .bold)).tracking(-0.2).foregroundStyle(DS.textPrimary)
                Text("for Mole CLI · \(Bundle.main.shortVersion)")
                    .font(Fonts.mono(11))
                    .foregroundStyle(DS.textFaint)
            }
        }
    }
}

private struct NavItem: View {
    @Environment(AppModel.self) private var app
    let module: Module
    let selected: Bool
    let namespace: Namespace.ID
    @State private var hovering = false

    var body: some View {
        Button { withAnimation(Motion.nav) { app.go(module) } } label: {
            HStack(spacing: 10) {
                StrokeIcon(data: module.icon)
                    .scaleEffect(selected ? 1.12 : 1)
                    .animation(Motion.spring(0.35, 0.5), value: selected)
                Text(module.title)
                    .font(Fonts.ui(14, .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                badge
            }
            .foregroundStyle(selected ? DS.textPrimary : DS.navIdle)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background {
                ZStack(alignment: .leading) {
                    if selected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DS.accentSelection)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(DS.accent)
                                    .frame(width: 3)
                                    .padding(.vertical, 9)
                                    .shadow(color: DS.accent, radius: 5)
                            }
                            .matchedGeometryEffect(id: "nav", in: namespace)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 8).fill(DS.surface)
                    }
                }
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.25), value: selected)
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
    }

    @ViewBuilder private var badge: some View {
        let live = liveBadge
        Group {
            if let live {
                CountingText(value: live) { Fmt.size($0) }
                    .counting(live, duration: 0.7)
                    .foregroundStyle(selected ? DS.accentLight : Color(hex: 0x6B7280))
            } else if module == .uninstall, app.uninstall.loaded {
                Text("\(app.uninstall.apps.count)")
                    .foregroundStyle(selected ? DS.accentLight : Color(hex: 0x6B7280))
            } else {
                Text("⌘\(module.index + 1)").foregroundStyle(DS.borderMuted)
            }
        }
        .font(Fonts.mono(11))
    }

    private var liveBadge: Double? {
        switch module {
        case .clean: app.clean.phase == .results ? app.clean.resultTotal : nil
        case .purge: app.purge.scanned ? app.purge.reclaimable : nil
        case .installers: app.installers.scanned ? app.installers.reclaimable : nil
        default: nil
        }
    }
}

private struct DiskWidget: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let disk = app.disk
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(disk.volumeName).font(Fonts.ui(12.5)).foregroundStyle(DS.textSecondary)
                Spacer()
                Text("\(Int((disk.usedFraction * 100).rounded()))%").font(Fonts.mono(12.5)).foregroundStyle(DS.textMuted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(DS.borderSubtle2)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(disk.usedFraction > 0.85 ? DS.warning : DS.accent)
                        .frame(width: geo.size.width * disk.usedFraction)
                        .animation(Motion.easeOut(1), value: disk.usedFraction)
                }
            }
            .frame(height: 6)
            HStack(spacing: 0) {
                CountingText(value: disk.free) { Fmt.size($0) }
                    .counting(disk.free, duration: 1.1)
                    .font(Fonts.mono(12))
                    .foregroundStyle(disk.tweening ? DS.success : DS.textPrimary)
                    .animation(.easeOut(duration: 0.4), value: disk.tweening)
                Text(" free of \(Fmt.size(disk.total))").font(Fonts.ui(12)).foregroundStyle(DS.textMuted)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(DS.bgDisk))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.borderSubtle, lineWidth: 1))
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}
