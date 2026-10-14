import SwiftUI

struct ListView: View {
    @Bindable var model: ListModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if model.phase == .done {
                        DoneBanner(text: "Moved \(Fmt.size(model.freed)) from \(model.freedCount) items to the Trash.")
                            .pop(duration: 0.45, from: 0.9)
                    }
                    Panel {
                        VStack(spacing: 0) {
                            if model.entries.isEmpty && (model.phase == .scanning || (!model.scanned && model.phase == .idle)) {
                                ForEach(0..<6, id: \.self) { i in SkeletonRow().rise(Double(i) * 0.05) }
                            } else {
                                ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                                    if !model.removed.contains(entry.id) {
                                        EntryRow(model: model, entry: entry)
                                            .rise(Motion.stagger(index), duration: 0.45)
                                            .transition(.asymmetric(insertion: .identity, removal: .opacity))
                                    }
                                }
                                if model.available.isEmpty && model.phase != .working && model.phase != .scanning {
                                    Text("All clear. Nothing left here.")
                                        .font(Fonts.ui(13.5))
                                        .foregroundStyle(DS.textFaint)
                                        .padding(28)
                                        .frame(maxWidth: .infinity)
                                        .fadeIn(0.4, delay: 0.2)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            footer
        }
        .pageEnter()
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reclaimable").cardLabel()
                CountingText(value: model.reclaimable) { Fmt.size($0) }
                    .counting(model.reclaimable, duration: 0.7)
                    .font(Fonts.mono(38, .medium))
                    .tracking(-1.2)
                Text(model.note)
                    .font(Fonts.ui(13.5))
                    .foregroundStyle(DS.textMuted)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
            LinkButton(title: "Select all", action: model.selectAll)
            LinkButton(title: "None", color: DS.textMuted, hoverColor: DS.textPrimary, action: model.selectNone)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.phase == .working {
                ProgressBar(fraction: model.totalCount > 0 ? Double(model.doneCount) / Double(model.totalCount) : 0)
                    .frame(maxWidth: 360)
                    .fadeIn()
            } else if model.phase == .scanning {
                HStack(spacing: 10) {
                    Spinner()
                    Text("Scanning with \(model.kind == .purge ? "mo purge" : "mo installer")…").font(Fonts.ui(13)).foregroundStyle(DS.textMuted)
                }
                .fadeIn()
            }
            Spacer()
            Text(summary).font(Fonts.ui(13)).foregroundStyle(DS.textMuted)
            if model.scanned && model.phase != .working {
                IconButton(size: 30, help: "Rescan (⌘R)", action: model.scan) {
                    Text("↻").font(.system(size: 14))
                }
            }
            Button(action: model.run) {
                if model.phase == .working {
                    Text("Working…")
                } else {
                    HStack(spacing: 0) {
                        Text(model.verb + " ")
                        CountingText(value: model.selectedTotal) { Fmt.size($0) }.counting(model.selectedTotal, duration: 0.5)
                    }
                }
            }
            .buttonStyle(PillButtonStyle(kind: .primary, enabled: model.selectedTotal > 0 && model.phase != .working && model.phase != .scanning))
            .disabled(model.selectedTotal <= 0 || model.phase == .working || model.phase == .scanning)
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
        .background(DS.bgFooter)
        .overlay(alignment: .top) { Rectangle().fill(DS.borderSubtle).frame(height: 1) }
    }

    private var summary: String {
        model.phase == .working
            ? "\(model.doneCount) of \(model.totalCount) removed"
            : "\(model.selectedEntries.count) of \(model.available.count) selected"
    }
}

private struct EntryRow: View {
    @Bindable var model: ListModel
    let entry: ListModel.Entry

    var body: some View {
        let isGone = model.gone.contains(entry.id)
        let on = model.selected.contains(entry.id)
        HStack(spacing: 14) {
            Checkbox(state: on ? .all : .none)
            Text(entry.tag)
                .font(Fonts.mono(11.5))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(DS.surfaceRaised))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(hex: 0x262A31), lineWidth: 1))
                .frame(minWidth: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(Fonts.mono(13)).lineLimit(1).truncationMode(.middle)
                Text(entry.sub).font(Fonts.ui(12.5)).foregroundStyle(DS.textMuted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if entry.recent { Tag(text: "recent", size: 11) }
            Text(Fmt.size(entry.bytes)).font(Fonts.mono(13)).foregroundStyle(DS.textSecondary).frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isGone ? 0 : 12)
        .frame(maxHeight: isGone ? 0 : 80)
        .opacity(isGone ? 0 : 1)
        .offset(x: isGone ? 60 : 0)
        .clipped()
        .contentShape(Rectangle())
        .hoverBackground(.clear, DS.surfaceHover)
        .overlay(alignment: .bottom) { Rectangle().fill(isGone ? .clear : DS.borderSubtle2).frame(height: 1) }
        .onTapGesture { withAnimation(Motion.bouncy) { model.toggle(entry) } }
        .help(entry.path)
    }
}

struct DoneBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text("✓").font(.system(size: 11))
                .frame(width: 18, height: 18)
                .background(Circle().fill(DS.success.opacity(0.18)))
            Text(text).font(Fonts.ui(13.5))
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.success)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x11241C)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0x1D4434), lineWidth: 1))
    }
}

/// Placeholder row with a shimmer while a scan runs.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 5).fill(DS.surfaceRaised).frame(width: 18, height: 18)
            RoundedRectangle(cornerRadius: 5).fill(DS.surfaceRaised).frame(width: 90, height: 18)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(DS.surfaceRaised).frame(width: 260, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(DS.surfaceRaised.opacity(0.7)).frame(width: 160, height: 9)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).fill(DS.surfaceRaised).frame(width: 56, height: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(Shimmer(period: 1.4, color: .white.opacity(0.04)))
        .overlay(alignment: .bottom) { Rectangle().fill(DS.borderSubtle2).frame(height: 1) }
    }
}
