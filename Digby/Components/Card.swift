import SwiftUI

/// Surface card: radius 14, padding 20. Lifts 2 px on hover with a cursor-following radial glow.
struct SpotCard<Content: View>: View {
    var glow: Color = DS.accent
    var glowOpacity: Double = 0.09
    var glowRadius: CGFloat = 380
    var padding: CGFloat = 20
    var lift = true
    @ViewBuilder var content: () -> Content

    @State private var hovering = false
    @State private var point: CGPoint = CGPoint(x: -400, y: -400)

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(DS.surface)
                    RadialGradient(colors: [glow.opacity(glowOpacity), .clear], center: .zero, startRadius: 0, endRadius: glowRadius * 0.7)
                        .offset(x: point.x, y: point.y)
                        .frame(width: 0, height: 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .opacity(hovering ? 1 : 0)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(hovering ? DS.borderHover : DS.border, lineWidth: 1))
            .offset(y: hovering && lift && !Motion.reduce ? -2 : 0)
            .animation(Motion.easeOut(0.3), value: hovering)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    point = p
                    if !hovering { hovering = true }
                case .ended:
                    hovering = false
                }
            }
    }
}

/// Plain bordered surface without hover behaviour (lists, tables).
struct Panel<Content: View>: View {
    var radius: CGFloat = 14
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(DS.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}
