import AppKit
import SwiftUI

/// Menu bar extra: free space plus "Quick clean (dry run)" (brief, phase 2).
/// Quick clean drives the shared `CleanModel`, so its results open straight into the Clean review.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            DiskSummary()
            if app.moAvailable {
                QuickClean(model: app.clean, review: { open(.clean) })
            } else {
                missingMole
            }
            Divider().overlay(DS.borderSubtle)
            footer
        }
        .padding(16)
        .frame(width: 300)
        .background(DS.bgApp)
        .preferredColorScheme(.dark)
        .onAppear { app.disk.refresh(animated: false) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("dg")
                .font(Fonts.mono(11, .semibold))
                .tracking(-0.5)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(DS.accent))
                .shadow(color: DS.accent.opacity(0.7), radius: 6, y: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text("Digby").font(Fonts.ui(14, .bold)).foregroundStyle(DS.textPrimary)
                Text("for Mole CLI").font(Fonts.mono(10.5)).foregroundStyle(DS.textFaint)
            }
            Spacer()
            IconButton(size: 26, help: "Open Digby", action: { open(nil) }) {
                Text("↗").font(.system(size: 13))
            }
            .accessibilityIdentifier("menubar.open")
        }
    }

    private var missingMole: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mole CLI not found").font(Fonts.ui(13.5, .semibold))
            Text("Install it with brew install mole, then open Digby.")
                .font(Fonts.ui(12.5))
                .foregroundStyle(DS.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(DS.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.border, lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 4) {
            MenuRowButton(title: "Status", shortcut: "⌘1") { open(.status) }
            MenuRowButton(title: "Analyze", shortcut: "⌘7") { open(.analyze) }
            Spacer()
            MenuRowButton(title: "About", shortcut: "") {
                openWindow(id: "about")
                NSApp.activate()
                dismiss()
            }
            MenuRowButton(title: "Quit", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityIdentifier("menubar.quit")
        }
    }

    /// Brings the main window forward, optionally on a module.
    private func open(_ module: Module?) {
        if let module { app.go(module) }
        openWindow(id: "main")
        NSApp.activate()
        dismiss()
    }
}

private struct DiskSummary: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let disk = app.disk
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(disk.volumeName).cardLabel(11)
                Spacer()
                Text("\(Int((disk.usedFraction * 100).rounded()))% used").font(Fonts.mono(11.5)).foregroundStyle(DS.textMuted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CountingText(value: disk.free) { Fmt.size($0) }
                    .counting(disk.free, duration: 1.1)
                    .font(Fonts.mono(28, .medium))
                    .tracking(-1)
                    .foregroundStyle(disk.tweening ? DS.success : DS.textPrimary)
                    .accessibilityLabel(Fmt.size(disk.free))
                    .accessibilityIdentifier("menubar.free")
                Text("free of \(Fmt.size(disk.total))").font(Fonts.ui(12.5)).foregroundStyle(DS.textMuted)
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
        }
    }
}

private struct QuickClean: View {
    @Environment(AppModel.self) private var app
    let model: CleanModel
    let review: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.phase {
            case .idle:
                text("Quick clean", "Preview what mo clean would free. Nothing is deleted.")
                Button("Quick clean (dry run)", action: model.startScan)
                    .buttonStyle(PillButtonStyle(kind: .primary, height: 34, fontSize: 13.5, horizontal: 16, glow: false))
                    .accessibilityIdentifier("menubar.quickClean")
            case .scanning, .cleaning:
                HStack {
                    Text(model.phase == .scanning ? "Scanning… \(Int(model.progress * 100))%" : "\(model.dryRun ? "Simulating" : "Cleaning")… \(Int(model.progress * 100))%")
                        .font(Fonts.ui(13.5, .semibold))
                        .accessibilityIdentifier("menubar.status")
                    Spacer()
                    if model.phase == .scanning {
                        LinkButton(title: "Stop", color: DS.textMuted, hoverColor: DS.danger, size: 12.5, action: model.cancel)
                    }
                }
                ProgressBar(fraction: model.progress, height: 4)
                Text(Fmt.tildePath(model.currentPath))
                    .font(Fonts.mono(11))
                    .foregroundStyle(DS.textFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .results:
                found(model.resultTotal, "found in \(model.categories.count) categories")
                Button("Review in Digby", action: review)
                    .buttonStyle(PillButtonStyle(kind: .primary, height: 34, fontSize: 13.5, horizontal: 16, glow: false))
                    .accessibilityIdentifier("menubar.review")
            case .done:
                found(model.freed, model.lastDry ? "could be freed" : "freed")
                HStack(spacing: 8) {
                    if model.lastDry {
                        Button("Review in Digby") { model.backToResults(); review() }
                            .buttonStyle(PillButtonStyle(kind: .primary, height: 34, fontSize: 13.5, horizontal: 16, glow: false))
                            .accessibilityIdentifier("menubar.review")
                    }
                    Button("Scan again", action: model.startScan)
                        .buttonStyle(PillButtonStyle(kind: .secondary, height: 34, fontSize: 13.5, horizontal: 16))
                }
            case .empty:
                text("Nothing to clean", "Caches and logs are already lean.")
                Button("Scan again", action: model.startScan)
                    .buttonStyle(PillButtonStyle(kind: .secondary, height: 34, fontSize: 13.5, horizontal: 16))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(DS.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.border, lineWidth: 1))
        .animation(Motion.easeOut(0.3), value: model.phase)
    }

    private func text(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Fonts.ui(13.5, .semibold)).accessibilityIdentifier("menubar.status")
            Text(subtitle).font(Fonts.ui(12.5)).foregroundStyle(DS.textMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func found(_ bytes: Double, _ caption: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CountingText(value: bytes) { Fmt.size($0) }
                .counting(bytes, duration: 0.8)
                .font(Fonts.mono(22, .medium))
                .foregroundStyle(DS.success)
                .accessibilityLabel(Fmt.size(bytes))
                .accessibilityIdentifier("menubar.found")
            Text(caption).font(Fonts.ui(12.5)).foregroundStyle(DS.textMuted)
        }
    }
}

private struct MenuRowButton: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(Fonts.ui(12.5)).foregroundStyle(hovering ? DS.textPrimary : DS.textSecondary)
                Text(shortcut).font(Fonts.mono(10.5)).foregroundStyle(DS.textFaint)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? DS.surfaceRaised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Status item: the Clean glyph plus free space.
struct MenuBarLabel: View {
    let disk: DiskInfo
    let showsFree: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Self.icon)
            if showsFree { Text(Self.short(disk.free)) }
        }
    }

    /// Compact form for the menu bar: "39 GB".
    static func short(_ bytes: Double) -> String {
        bytes >= 1e12 ? String(format: "%.1f TB", bytes / 1e12) : "\(Int((bytes / 1e9).rounded())) GB"
    }

    /// Template image from the design's Clean icon so it adapts to light and dark menu bars.
    static let icon: NSImage = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: true) { rect in
            let path = SVGPath.parse(Module.clean.icon)
                .applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(path.cgPath)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.9 * rect.width / 24)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
