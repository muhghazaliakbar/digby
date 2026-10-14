import SwiftUI

// MARK: - Checkbox

enum CheckState { case none, some, all }

/// Tri-state checkbox: 18 px (radius 5) or 16 px (radius 4), bouncy spring.
struct Checkbox: View {
    var state: CheckState
    var size: CGFloat = 18
    var tint: Color = DS.accent
    var dimmed = false

    var body: some View {
        let on = state != .none
        RoundedRectangle(cornerRadius: size >= 18 ? 5 : 4)
            .fill(on ? tint : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: size >= 18 ? 5 : 4)
                    .strokeBorder(on ? tint : DS.borderMuted, lineWidth: 1.5)
            )
            .overlay {
                Group {
                    switch state {
                    case .all: Text("✓")
                    case .some: Text("–")
                    case .none: EmptyView()
                    }
                }
                .font(.system(size: size >= 18 ? 12 : 11, weight: .bold))
                .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .scaleEffect(on ? 1 : 0.92)
            .opacity(dimmed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.18), value: on)
            .animation(Motion.spring(0.3, 0.45), value: state)
    }
}

// MARK: - Toggle

/// 36×22 switch with a bouncy 16 px knob.
struct ToggleSwitch: View {
    var isOn: Bool
    var action: () -> Void
    var enabled = true

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                Capsule().fill(isOn ? DS.accent : DS.borderStrong)
                    .animation(.easeOut(duration: 0.25), value: isOn)
                Circle().fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                    .offset(x: isOn ? 17 : 3)
                    .animation(Motion.bouncy, value: isOn)
            }
            .frame(width: 36, height: 22)
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .disabled(!enabled)
    }
}

// MARK: - Buttons

/// Scales on press; used where a button needs no other chrome.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !Motion.reduce ? scale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

enum PillKind { case primary, secondary, danger, muted }

/// Pill button: hover lifts −2 px, press scales to 0.95.
struct PillButtonStyle: ButtonStyle {
    var kind: PillKind = .primary
    var height: CGFloat = 42
    var fontSize: CGFloat = 15
    var horizontal: CGFloat = 26
    var enabled = true
    var hoverScale: CGFloat = 1
    var glow = true

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, style: self)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let style: PillButtonStyle
        @State private var hovering = false

        var body: some View {
            let hot = hovering && style.enabled
            configuration.label
                .font(Fonts.ui(style.fontSize, style.kind == .secondary ? .medium : .semibold))
                .foregroundStyle(foreground(hot))
                .padding(.horizontal, style.horizontal)
                .frame(height: style.height)
                .background(Capsule().fill(background(hot)))
                .overlay {
                    if style.kind == .secondary {
                        Capsule().strokeBorder(hot ? DS.accent : DS.borderStrong, lineWidth: 1)
                    }
                }
                .shadow(color: shadowColor.opacity(style.glow && style.enabled ? (hot ? 0.9 : 0.7) : 0),
                        radius: hot ? 16 : 12, y: hot ? 12 : 9)
                .opacity(style.enabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && style.enabled ? 0.95 : (hot ? style.hoverScale : 1))
                .offset(y: hot && !configuration.isPressed ? -2 : 0)
                .animation(Motion.overshoot(0.2, 1.6), value: hot)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }

        private var shadowColor: Color {
            switch style.kind {
            case .primary: DS.accent
            case .danger: DS.danger
            default: .clear
            }
        }

        private func foreground(_ hot: Bool) -> Color {
            switch style.kind {
            case .secondary: DS.textPrimary
            case .muted: DS.textSecondary
            default: .white
            }
        }

        private func background(_ hot: Bool) -> Color {
            switch style.kind {
            case .primary: hot ? DS.accentHover : DS.accent
            case .danger: hot ? DS.dangerHover : DS.danger
            case .muted: Color(hex: 0x2A3A55)
            case .secondary: .clear
            }
        }
    }
}

/// Text-only link button ("Select all", "None", "See what is using space →").
struct LinkButton: View {
    let title: String
    var color: Color = DS.accent
    var hoverColor: Color = DS.accentLight
    var size: CGFloat = 13
    var nudge: CGFloat = 0
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fonts.ui(size))
                .foregroundStyle(hovering ? hoverColor : color)
                .padding(nudge == 0 ? 4 : 0)
                .offset(x: hovering ? nudge : 0)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.easeOut(0.2)) { hovering = h } }
    }
}

/// Small square icon button used in lists and the breadcrumb bar.
struct IconButton<Label: View>: View {
    var size: CGFloat = 24
    var hoverBackground: Color = Color(hex: 0x262A31)
    var hoverForeground: Color = DS.textPrimary
    var foreground: Color = DS.textMuted
    var nudge: CGFloat = 0
    var help: String = ""
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(hovering ? hoverForeground : foreground)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? hoverBackground : .clear))
                .offset(x: hovering ? nudge : 0)
        }
        .buttonStyle(PressStyle(scale: 0.85))
        .help(help)
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
    }
}

// MARK: - Rows

/// Background that switches to a hover color, like the design's `style-hover`.
struct HoverBackground: ViewModifier {
    var base: Color = .clear
    var hover: Color = DS.surfaceHover
    var radius: CGFloat = 0
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(hovering ? hover : base))
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

extension View {
    func hoverBackground(_ base: Color = .clear, _ hover: Color = DS.surfaceHover, radius: CGFloat = 0) -> some View {
        modifier(HoverBackground(base: base, hover: hover, radius: radius))
    }
}

// MARK: - Tag chips

struct Tag: View {
    let text: String
    var color: Color = DS.warning
    var background: Color = Color(hex: 0x2A2416)
    var size: CGFloat = 10.5

    var body: some View {
        Text(text)
            .font(Fonts.mono(size))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(background))
    }
}

// MARK: - Progress

/// Thin progress bar with an optional glowing, shimmering fill.
struct ProgressBar: View {
    var fraction: Double
    var color: Color = DS.accent
    var height: CGFloat = 6
    var shimmer = true
    var glow = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2).fill(DS.surfaceTrack)
                ZStack {
                    color
                    if shimmer { Shimmer(period: 1, color: .white.opacity(0.5)) }
                }
                .frame(width: geo.size.width * min(max(fraction, 0), 1))
                .clipShape(RoundedRectangle(cornerRadius: height / 2))
                .shadow(color: glow ? color : .clear, radius: 6)
                .animation(Motion.easeOut(0.3), value: fraction)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2))
    }
}
