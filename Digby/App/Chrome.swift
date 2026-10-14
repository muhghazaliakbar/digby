import SwiftUI

// MARK: - Header

struct HeaderBar: View {
    @Environment(AppModel.self) private var app
    @State private var copyHover = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(app.view.title)
                    .font(Fonts.ui(19, .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(DS.textPrimary)
                Text(app.view.subtitle)
                    .font(Fonts.ui(13.5))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .id(app.view)
            .slideIn(0.4)
            .frame(maxWidth: .infinity, alignment: .leading)

            if app.moAvailable {
                Button(action: app.copyCommand) {
                    HStack(spacing: 8) {
                        Text("$").foregroundStyle(DS.accent)
                        Text(app.command).foregroundStyle(copyHover ? DS.textPrimary : DS.textSecondary)
                        Text(app.copied ? "copied ✓" : "copy")
                            .font(Fonts.mono(11))
                            .foregroundStyle(app.copied ? DS.success : DS.textFaint)
                    }
                    .font(Fonts.mono(12.5))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(DS.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(app.copied ? Color(hex: 0x1D4434) : DS.border, lineWidth: 1))
                    .animation(.easeOut(duration: 0.25), value: app.copied)
                }
                .buttonStyle(PressStyle(scale: 0.96))
                .help("Copy the equivalent CLI command")
                .onHover { copyHover = $0 }
            }

            Button(action: app.toggleTerminal) {
                Text(">_")
                    .font(Fonts.mono(12.5))
                    .foregroundStyle(app.termOpen ? DS.accentLight : DS.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(app.termOpen ? DS.accentSelection : DS.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(app.termOpen ? Color(hex: 0x2B4A7A) : DS.border, lineWidth: 1))
                    .animation(.easeOut(duration: 0.25), value: app.termOpen)
            }
            .buttonStyle(PressStyle(scale: 0.94))
            .help("Toggle terminal (⌘J)")
        }
        .padding(.leading, 26)
        .padding(.trailing, 18)
        .frame(height: 60)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.borderSubtle).frame(height: 1) }
    }
}

// MARK: - Terminal drawer

struct TerminalDrawer: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("TERMINAL").foregroundStyle(DS.textMuted)
                Text("zsh · ~/")
                Spacer()
                DrawerButton(title: "clear") { app.terminal.clear() }
                DrawerButton(title: "×", size: 14) { app.toggleTerminal() }
            }
            .font(Fonts.mono(11.5))
            .foregroundStyle(DS.textFaint)
            .padding(.leading, 20)
            .padding(.trailing, 14)
            .frame(height: 34)
            .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x15171B)).frame(height: 1) }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(app.terminal.lines) { line in
                            TerminalLine(text: line.text, color: line.kind.color)
                        }
                        HStack(spacing: 0) {
                            Text("$ ")
                            BlinkingCursor()
                        }
                        .foregroundStyle(DS.accent)
                        .id("cursor")
                    }
                    .font(Fonts.mono(12.5))
                    .lineSpacing(12.5 * 0.65 - 4)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
                .onChange(of: app.terminal.lines.last?.id) { proxy.scrollTo("cursor", anchor: .bottom) }
                .onChange(of: app.termOpen) { if app.termOpen { proxy.scrollTo("cursor", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("cursor", anchor: .bottom) }
            }
        }
        .frame(height: 210)
        .background(DS.bgDrawer)
    }
}

private struct TerminalLine: View {
    let text: String
    let color: Color
    @State private var shown = false

    var body: some View {
        Text(text)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 20.6, alignment: .leading)
            .opacity(shown ? 1 : 0)
            .offset(x: shown || Motion.reduce ? 0 : -6)
            .onAppear { withAnimation(.easeOut(duration: 0.25)) { shown = true } }
    }
}

private struct DrawerButton: View {
    let title: String
    var size: CGFloat = 11.5
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fonts.mono(size))
                .foregroundStyle(hovering ? DS.textPrimary : DS.textFaint)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Toasts

struct ToastStack: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(app.toasts) { toast in
                ToastView(toast: toast)
                    .transition(.asymmetric(
                        insertion: .modifier(active: ToastEnter(progress: 0), identity: ToastEnter(progress: 1)),
                        removal: .opacity
                    ))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(!app.toasts.isEmpty)
    }
}

private struct ToastEnter: ViewModifier {
    var progress: Double
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(Motion.reduce ? 1 : 0.94 + 0.06 * progress)
            .offset(y: Motion.reduce ? 0 : 18 * (1 - progress))
    }
}

private struct ToastView: View {
    let toast: Toast
    @State private var timer: CGFloat = 1

    var body: some View {
        HStack(spacing: 12) {
            Text("✓")
                .font(.system(size: 13))
                .foregroundStyle(toast.color)
                .frame(width: 26, height: 26)
                .background(Circle().fill(toast.color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(Fonts.ui(14, .semibold)).foregroundStyle(DS.textPrimary)
                Text(toast.subtitle).font(Fonts.mono(12.5)).foregroundStyle(DS.textMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(minWidth: 260, maxWidth: 340, alignment: .leading)
        .fixedSize()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x181B21, opacity: 0.94)))
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Rectangle().fill(toast.color)
                    .frame(width: geo.size.width * timer, height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.7), radius: 22, y: 20)
        .opacity(toast.leaving ? 0 : 1)
        .offset(x: toast.leaving ? 40 : 0)
        .onAppear { withAnimation(.linear(duration: 3.5)) { timer = 0 } }
    }
}
