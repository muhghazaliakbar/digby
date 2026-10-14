import SwiftUI

// MARK: - Entrances

/// Page change: fade in from y+10 with blur 4→0 over 0.45 s.
struct PageEnter: ViewModifier {
    var duration: Double = 0.45
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || Motion.reduce ? 0 : 10)
            .blur(radius: shown || Motion.reduce ? 0 : 4)
            .onAppear { withAnimation(Motion.easeOut(duration)) { shown = true } }
    }
}

/// Cards and rows enter from y+14 with a per-index delay.
struct Rise: ViewModifier {
    var delay: Double
    var distance: CGFloat = 14
    var duration: Double = 0.5
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || Motion.reduce ? 0 : distance)
            .onAppear { withAnimation(Motion.easeOut(duration).delay(Motion.reduce ? 0 : delay)) { shown = true } }
    }
}

/// `mo-pop`: scale .6 → 1 with overshoot.
struct Pop: ViewModifier {
    var delay: Double = 0
    var duration: Double = 0.5
    var from: CGFloat = 0.6
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || Motion.reduce ? 1 : from)
            .onAppear { withAnimation(Motion.overshoot(duration, 1.6).delay(Motion.reduce ? 0 : delay)) { shown = true } }
    }
}

/// `mo-swap`: slide in from x+18.
struct SlideIn: ViewModifier {
    var duration: Double = 0.4
    var distance: CGFloat = 18
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown || Motion.reduce ? 0 : distance)
            .onAppear { withAnimation(Motion.easeOut(duration)) { shown = true } }
    }
}

struct FadeIn: ViewModifier {
    var duration: Double = 0.3
    var delay: Double = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.easeOut(duration: duration).delay(delay)) { shown = true } }
    }
}

extension View {
    func pageEnter(_ duration: Double = 0.45) -> some View { modifier(PageEnter(duration: duration)) }
    func rise(_ delay: Double = 0, distance: CGFloat = 14, duration: Double = 0.5) -> some View {
        modifier(Rise(delay: delay, distance: distance, duration: duration))
    }
    func pop(_ delay: Double = 0, duration: Double = 0.5, from: CGFloat = 0.6) -> some View {
        modifier(Pop(delay: delay, duration: duration, from: from))
    }
    func slideIn(_ duration: Double = 0.4, distance: CGFloat = 18) -> some View { modifier(SlideIn(duration: duration, distance: distance)) }
    func fadeIn(_ duration: Double = 0.3, delay: Double = 0) -> some View { modifier(FadeIn(duration: duration, delay: delay)) }
}

// MARK: - Looping effects

/// Blinking block cursor (`mo-blink 1.1s steps(1)`).
struct BlinkingCursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { ctx in
            let on = Int(ctx.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            Text("▍").opacity(on ? 1 : 0)
        }
    }
}

// MARK: - Numbers

/// Counts to a new value over `duration` with easeOutCubic.
struct CountingText: View, Animatable {
    var value: Double
    var format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

extension View {
    /// Animates `CountingText` children when `value` changes.
    func counting(_ value: Double, duration: Double = 1.0) -> some View {
        animation(Motion.count(duration), value: value)
    }
}

// MARK: - Sparkline

nonisolated struct Sparkline: Shape {
    var values: [Double]
    var maxValue: Double
    var closed = false

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count > 1 else { return p }
        // Design: viewBox 0 0 100 40, y = 39 − v/max·36.
        let pts = values.enumerated().map { i, v in
            CGPoint(x: rect.width * CGFloat(i) / CGFloat(values.count - 1),
                    y: rect.height * (39 - CGFloat(min(max(v / max(maxValue, 0.0001), 0), 1)) * 36) / 40)
        }
        if closed { p.move(to: CGPoint(x: 0, y: rect.height)); p.addLine(to: pts[0]) } else { p.move(to: pts[0]) }
        pts.dropFirst().forEach { p.addLine(to: $0) }
        if closed { p.addLine(to: CGPoint(x: rect.width, y: rect.height)); p.closeSubpath() }
        return p
    }
}
