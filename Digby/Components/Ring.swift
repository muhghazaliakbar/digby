import SwiftUI

struct RingSegment: Identifiable, Equatable {
    var id: String
    var fraction: Double
    var color: Color
}

/// Segmented ring: conic segments clockwise from 12 o'clock over a track, cut by tick marks
/// (the design's `repeating-conic-gradient` overlay).
struct SegmentedRing: View {
    var segments: [RingSegment]
    var track: Color = DS.surfaceTrack
    var thickness: CGFloat
    var tickEvery: Double = 6
    var tickWidth: Double = 1.2
    var tickColor: Color = DS.bgApp

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .inset(by: thickness / 2)
                    .stroke(track, lineWidth: thickness)
                ForEach(Array(starts.enumerated()), id: \.element.0.id) { _, pair in
                    let (seg, start) = pair
                    Circle()
                        .inset(by: thickness / 2)
                        .trim(from: min(start, 1), to: min(start + max(seg.fraction, 0), 1))
                        .stroke(seg.color, style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                Ticks(every: tickEvery, width: tickWidth, inner: d / 2 - thickness - 1)
                    .fill(tickColor)
            }
            .frame(width: d, height: d)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var starts: [(RingSegment, Double)] {
        var acc = 0.0
        return segments.map { seg in
            defer { acc += max(seg.fraction, 0) }
            return (seg, acc)
        }
    }

    nonisolated private struct Ticks: Shape {
        var every: Double
        var width: Double
        var inner: CGFloat

        func path(in rect: CGRect) -> Path {
            var p = Path()
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let outer = min(rect.width, rect.height) / 2 + 1
            var a = 0.0
            while a < 360 {
                let a0 = Angle.degrees(a - 90), a1 = Angle.degrees(a + width - 90)
                p.addArc(center: c, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
                p.addArc(center: c, radius: max(inner, 0), startAngle: a1, endAngle: a0, clockwise: true)
                p.closeSubpath()
                a += every
            }
            return p
        }
    }
}

/// Center disc of the big rings: radial gradient #171B22 → #0E1013 with a subtle border.
struct RingCenter<Content: View>: View {
    var inset: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(hex: 0x171B22), DS.bgApp], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 140))
            .overlay(Circle().strokeBorder(DS.borderSubtle, lineWidth: 1))
            .overlay(content())
            .padding(inset)
    }
}
