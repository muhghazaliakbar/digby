import SwiftUI

struct UninstallView: View {
    @Bindable var model: UninstallModel

    var body: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < 900
            HStack(spacing: 0) {
                AppListColumn(model: model)
                    .frame(width: narrow ? min(max(geo.size.width * 0.3, 220), 260) : min(max(geo.size.width * 0.3, 280), 340))
                    .overlay(alignment: .trailing) { Rectangle().fill(DS.borderSubtle).frame(width: 1) }
                if let app = model.current {
                    AppDetail(model: model, entry: app, kindWidth: narrow ? 66 : 86)
                        .id("\(app.id)#\(model.selectionChanges)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.loading {
                    VStack(spacing: 12) {
                        Spinner(size: 18)
                        Text("Reading installed apps…").font(Fonts.ui(13.5)).foregroundStyle(DS.textMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer()
                }
            }
        }
        .pageEnter()
    }
}

// MARK: - Left column

private struct AppListColumn: View {
    @Bindable var model: UninstallModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                TextField("", text: $model.query, prompt: Text("Search \(model.apps.count) apps").foregroundColor(DS.textFaint))
                    .textFieldStyle(.plain)
                    .font(Fonts.ui(14))
                    .foregroundStyle(DS.textPrimary)
                    .focused($searchFocused)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 9).fill(DS.surface))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(searchFocused ? DS.accent : DS.border, lineWidth: 1))
                    .background(RoundedRectangle(cornerRadius: 9).stroke(DS.accent.opacity(searchFocused ? 0.18 : 0), lineWidth: 6))
                    .animation(.easeOut(duration: 0.2), value: searchFocused)
                SortControl(model: model)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    let list = model.visible
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                        AppRow(model: model, entry: entry)
                            .rise(Motion.stagger(index), duration: 0.45)
                    }
                    if list.isEmpty && model.loaded {
                        Text("No apps match.").font(Fonts.ui(13.5)).foregroundStyle(DS.textFaint).padding(24).fadeIn()
                    }
                    if model.loading && model.apps.isEmpty {
                        ForEach(0..<8, id: \.self) { _ in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 9).fill(DS.surfaceRaised).frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 4).fill(DS.surfaceRaised).frame(width: 120, height: 11)
                                    RoundedRectangle(cornerRadius: 4).fill(DS.surfaceRaised.opacity(0.7)).frame(width: 80, height: 9)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .overlay(Shimmer(period: 1.4, color: .white.opacity(0.04)))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }
}

private struct SortControl: View {
    @Bindable var model: UninstallModel

    var body: some View {
        GeometryReader { geo in
            let w = (geo.size.width - 6 - 8) / 3
            let index = CGFloat(UninstallModel.Sort.allCases.firstIndex(of: model.sort) ?? 0)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x262B33))
                    .frame(width: w, height: 26)
                    .offset(x: index * (w + 4))
                    .animation(Motion.overshoot(0.4, 1.3), value: model.sort)
                HStack(spacing: 4) {
                    ForEach(UninstallModel.Sort.allCases, id: \.self) { sort in
                        Button { model.sort = sort } label: {
                            Text(sort.rawValue)
                                .font(Fonts.ui(12.5))
                                .foregroundStyle(model.sort == sort ? DS.textPrimary : DS.textMuted)
                                .frame(width: w, height: 26)
                                .contentShape(Rectangle())
                                .animation(.easeOut(duration: 0.25), value: model.sort)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(3)
        }
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9).fill(DS.surface))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DS.border, lineWidth: 1))
    }
}

private struct AppRow: View {
    @Bindable var model: UninstallModel
    let entry: UninstallModel.AppEntry
    @State private var hovering = false

    var body: some View {
        let on = entry.id == model.current?.id
        let hidden = on && model.phase == .closing
        HStack(spacing: 12) {
            Image(nsImage: model.icon(for: entry))
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(Fonts.ui(14, .medium)).lineLimit(1)
                Text("Opened \(Fmt.relative(entry.lastUsed).lowercased())").font(Fonts.ui(12)).foregroundStyle(DS.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.measured ? Fmt.size(entry.total) : "…")
                .font(Fonts.mono(12.5))
                .foregroundStyle(DS.textSecondary)
                .fixedSize()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, hidden ? 0 : 8)
        .frame(maxHeight: hidden ? 0 : 60)
        .opacity(hidden ? 0 : 1)
        .clipped()
        .background(RoundedRectangle(cornerRadius: 10).fill(on ? DS.accentSelection : hovering ? DS.surface : .clear))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
        .onTapGesture { model.select(entry) }
        .animation(Motion.easeOut(0.45), value: hidden)
    }
}

// MARK: - Detail

private struct AppDetail: View {
    @Bindable var model: UninstallModel
    let entry: UninstallModel.AppEntry
    let kindWidth: CGFloat

    var body: some View {
        let removing = model.phase != .idle
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 18) {
                    Image(nsImage: model.icon(for: entry))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .shadow(color: .black.opacity(0.5), radius: 15, y: 14)
                        .modifier(SuckToTrash(active: model.phase == .closing))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).font(Fonts.ui(24, .semibold)).tracking(-0.3).lineLimit(1)
                        Text("Version \(entry.version.isEmpty ? "—" : entry.version) · Last opened \(Fmt.relative(entry.lastUsed).lowercased())")
                            .font(Fonts.ui(13.5))
                            .foregroundStyle(DS.textMuted)
                    }
                    .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 2) {
                        CountingText(value: model.total(for: entry)) { Fmt.size($0) }
                            .counting(model.total(for: entry), duration: 0.6)
                            .font(Fonts.mono(26, .medium))
                        Text("will be removed").font(Fonts.ui(12.5)).foregroundStyle(DS.textMuted)
                    }
                }

                Panel(padding: 6) {
                    VStack(spacing: 0) {
                        let bundleGone = removing && model.step >= 0
                        HStack(spacing: 12) {
                            Checkbox(state: .all, size: 16, tint: bundleGone ? DS.success : DS.accent).opacity(0.7)
                            Text("App bundle").font(Fonts.mono(11)).foregroundStyle(DS.textSecondary).lineLimit(1).frame(width: kindWidth, alignment: .leading)
                            Text(Fmt.tildePath(entry.path)).font(Fonts.mono(12.5)).foregroundStyle(DS.textSecondary)
                                .strikethrough(bundleGone).lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(entry.measured ? Fmt.size(entry.bundleBytes) : "…").font(Fonts.mono(12.5)).foregroundStyle(DS.textMuted).fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                        .opacity(bundleGone ? 0.35 : 1)
                        .offset(x: bundleGone ? 14 : 0)

                        ForEach(Array(entry.leftovers.enumerated()), id: \.element.id) { index, leftover in
                            LeftoverRow(model: model, leftover: leftover, kindWidth: kindWidth)
                                .rise(0.08 + Double(index) * 0.045, duration: 0.45)
                        }
                        if !entry.measured {
                            HStack(spacing: 10) {
                                Spinner()
                                Text("Looking for leftovers…").font(Fonts.ui(12.5)).foregroundStyle(DS.textMuted)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 40)
                            .overlay(alignment: .top) { Rectangle().fill(DS.borderSubtle2).frame(height: 1) }
                        }
                    }
                }

                HStack(spacing: 16) {
                    if model.phase == .idle {
                        Button("Uninstall \(entry.name)", action: model.uninstall)
                            .buttonStyle(PillButtonStyle(kind: .danger, horizontal: 24))
                        Text("\(entry.leftovers.count) leftover location\(entry.leftovers.count == 1 ? "" : "s") found. Checked items move to the Trash.")
                            .font(Fonts.ui(13))
                            .foregroundStyle(DS.textMuted)
                            .frame(minWidth: 220, alignment: .leading)
                    } else {
                        HStack(spacing: 14) {
                            ProgressBar(fraction: model.steps.isEmpty ? 0 : Double(model.step + 1) / Double(model.steps.count), color: DS.danger)
                                .frame(maxWidth: 360)
                            Text("Removing \(entry.name)…").font(Fonts.ui(13)).foregroundStyle(DS.textMuted)
                        }
                        .fadeIn()
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .slideIn(0.45)
    }
}

private struct LeftoverRow: View {
    @Bindable var model: UninstallModel
    let leftover: UninstallModel.Leftover
    let kindWidth: CGFloat

    var body: some View {
        let (kind, color) = AppScanner.kind(of: leftover.path)
        let index = model.steps.firstIndex(of: leftover.path)
        let gone = model.phase != .idle && index.map { $0 <= model.step } == true
        let on = !model.unchecked.contains(leftover.path)
        HStack(spacing: 12) {
            Checkbox(state: on || gone ? .all : .none, size: 16, tint: gone ? DS.success : DS.accent)
            Text(kind).font(Fonts.mono(11)).foregroundStyle(color).lineLimit(1).frame(width: kindWidth, alignment: .leading)
            Text(Fmt.tildePath(leftover.path)).font(Fonts.mono(12.5)).foregroundStyle(DS.textSecondary)
                .strikethrough(gone).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.size(leftover.bytes)).font(Fonts.mono(12.5)).foregroundStyle(DS.textMuted).fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .contentShape(Rectangle())
        .hoverBackground(.clear, DS.surfaceRaised, radius: 8)
        .overlay(alignment: .top) { Rectangle().fill(DS.borderSubtle2).frame(height: 1) }
        .opacity(gone ? 0.35 : 1)
        .offset(x: gone ? 14 : 0)
        .onTapGesture { withAnimation(Motion.bouncy) { model.toggle(leftover) } }
        .help(leftover.path)
    }
}

/// `mo-suck`: icon shrinks and flies toward the Dock's Trash.
private struct SuckToTrash: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? 0.15 : 1)
            .rotationEffect(.degrees(active ? -12 : 0))
            .offset(x: active ? -160 : 0, y: active ? 40 : 0)
            .opacity(active ? 0 : 1)
            .animation(Motion.easeIn(0.5), value: active)
    }
}
