import AppKit
import QuartzCore
import SwiftUI

/// Hosts Core Animation layers for looping effects. Infinite animations run in the render server,
/// like CSS keyframes, instead of re-evaluating SwiftUI every frame.
struct LayerEffect: NSViewRepresentable {
    /// Rebuilds sublayers whenever the view's size changes.
    let build: (CALayer, CGSize) -> Void
    var coreImage = false

    func makeNSView(context: Context) -> EffectView {
        let view = EffectView()
        view.build = build
        view.layerUsesCoreImageFilters = coreImage
        return view
    }

    func updateNSView(_ nsView: EffectView, context: Context) {}

    final class EffectView: NSView {
        var build: ((CALayer, CGSize) -> Void)?
        private var builtSize: CGSize = .zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            rebuildIfNeeded()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            builtSize = .zero
            rebuildIfNeeded()
        }

        private func rebuildIfNeeded() {
            guard let layer, window != nil, bounds.size != builtSize, bounds.width > 0, bounds.height > 0 else { return }
            builtSize = bounds.size
            layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            build?(layer, bounds.size)
            CATransaction.commit()
        }
    }
}

enum Loop {
    static func basic(_ keyPath: String, from: Any?, to: Any?, duration: Double, timing: CAMediaTimingFunction = .init(name: .linear),
                      autoreverses: Bool = false, delay: Double = 0) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: keyPath)
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.timingFunction = timing
        a.autoreverses = autoreverses
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        a.beginTime = CACurrentMediaTime() + delay
        a.fillMode = .backwards
        return a
    }

    static func rotation(_ layer: CALayer, period: Double) {
        guard !Motion.reduce else { return }
        layer.add(basic("transform.rotation.z", from: 0, to: Double.pi * 2, duration: period), forKey: "spin")
    }

    static func cgColor(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - Effects

/// Primary Scan button ripples: two capsule rings, 2.4 s, offset 1.2 s.
struct RippleRings: View {
    var body: some View {
        LayerEffect { root, size in
            guard !Motion.reduce else { return }
            for delay in [0.0, 1.2] {
                let ring = CAShapeLayer()
                ring.frame = CGRect(origin: .zero, size: size)
                ring.path = CGPath(roundedRect: ring.bounds.insetBy(dx: 0.75, dy: 0.75), cornerWidth: size.height / 2 - 0.75, cornerHeight: size.height / 2 - 0.75, transform: nil)
                ring.fillColor = nil
                ring.strokeColor = Loop.cgColor(0x3D8BFF, 0.7)
                ring.lineWidth = 1.5
                ring.opacity = 0
                let group = CAAnimationGroup()
                let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.6, 0.3, 1)
                let sx = CABasicAnimation(keyPath: "transform.scale.x"); sx.fromValue = 1; sx.toValue = 1.55
                let sy = CABasicAnimation(keyPath: "transform.scale.y"); sy.fromValue = 1; sy.toValue = 1.9
                let op = CABasicAnimation(keyPath: "opacity"); op.fromValue = 0.7 / 0.7; op.toValue = 0
                group.animations = [sx, sy, op]
                group.duration = 2.4
                group.timingFunction = timing
                group.repeatCount = .infinity
                group.isRemovedOnCompletion = false
                group.beginTime = CACurrentMediaTime() + delay
                root.addSublayer(ring)
                ring.add(group, forKey: "ripple")
            }
        }
        .allowsHitTesting(false)
    }
}

/// Idle halo around the ring, breathing over 3.4 s.
struct BreathingHalo: View {
    var body: some View {
        LayerEffect { root, size in
            let g = CAGradientLayer()
            g.type = .radial
            g.frame = CGRect(origin: .zero, size: size)
            // CSS `radial-gradient(circle, …)` sizes to the farthest corner (√2 × radius).
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 0.5 + 0.7071, y: 0.5 + 0.7071)
            let c = Loop.cgColor(0x3D8BFF, 0.22), clear = Loop.cgColor(0x3D8BFF, 0)
            g.colors = [clear, clear, c, clear, clear]
            g.locations = [0, 0.56, 0.64, 0.71, 1]
            root.addSublayer(g)
            guard !Motion.reduce else { return }
            let ease = CAMediaTimingFunction(name: .easeInEaseOut)
            g.add(Loop.basic("opacity", from: 0.35, to: 1, duration: 1.7, timing: ease, autoreverses: true), forKey: "o")
            g.add(Loop.basic("transform.scale", from: 0.985, to: 1.02, duration: 1.7, timing: ease, autoreverses: true), forKey: "s")
        }
        .allowsHitTesting(false)
    }
}

/// Rotating comet glow behind the ring while busy.
struct CometGlow: View {
    let hex: UInt32

    var body: some View {
        LayerEffect(build: { root, size in
            let g = CAGradientLayer()
            g.type = .conic
            g.frame = CGRect(origin: .zero, size: size)
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 0.5, y: 0)
            let clear = Loop.cgColor(hex, 0)
            g.colors = [clear, clear, Loop.cgColor(hex, 0.55)]
            g.locations = [0, NSNumber(value: 240.0 / 360), 1]
            let mask = CAShapeLayer()
            mask.path = CGPath(ellipseIn: g.bounds, transform: nil)
            g.mask = mask
            if let blur = CIFilter(name: "CIGaussianBlur") {
                blur.setValue(12, forKey: kCIInputRadiusKey)
                let holder = CALayer()
                holder.frame = g.frame
                holder.filters = [blur]
                holder.addSublayer(g)
                root.addSublayer(holder)
                Loop.rotation(holder, period: 1.4)
            } else {
                root.addSublayer(g)
                Loop.rotation(g, period: 1.4)
            }
        }, coreImage: true)
        .allowsHitTesting(false)
    }
}

/// White dot orbiting the ring track.
struct OrbitDot: View {
    let hex: UInt32

    var body: some View {
        LayerEffect { root, size in
            let orbit = CALayer()
            orbit.frame = CGRect(origin: .zero, size: size)
            let dot = CALayer()
            dot.frame = CGRect(x: size.width / 2 - 4, y: 9, width: 8, height: 8)
            dot.cornerRadius = 4
            dot.backgroundColor = .white
            dot.shadowColor = Loop.cgColor(hex, 0.9)
            dot.shadowOpacity = 1
            dot.shadowRadius = 9
            dot.shadowOffset = .zero
            orbit.addSublayer(dot)
            root.addSublayer(orbit)
            Loop.rotation(orbit, period: 1.4)
        }
        .allowsHitTesting(false)
    }
}

/// Highlight sweeping left → right (`mo-shimmer`).
struct Shimmer: View {
    var period: Double = 2
    var color: Color = .white.opacity(0.45)

    var body: some View {
        let cg = NSColor(color).cgColor
        LayerEffect { root, size in
            root.masksToBounds = true
            let g = CAGradientLayer()
            g.frame = CGRect(origin: .zero, size: size)
            g.startPoint = CGPoint(x: 0, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 0.5)
            g.colors = [cg.copy(alpha: 0)!, cg, cg.copy(alpha: 0)!]
            root.addSublayer(g)
            guard !Motion.reduce else { g.opacity = 0; return }
            g.add(Loop.basic("transform.translation.x", from: -size.width, to: size.width, duration: period), forKey: "shimmer")
        }
        .allowsHitTesting(false)
    }
}

/// 13 px ring spinner (`mo-spin .7s`).
struct Spinner: View {
    var size: CGFloat = 13

    var body: some View {
        LayerEffect { root, s in
            let inset: CGFloat = 1
            let rect = CGRect(origin: .zero, size: s).insetBy(dx: inset, dy: inset)
            let track = CAShapeLayer()
            track.path = CGPath(ellipseIn: rect, transform: nil)
            track.fillColor = nil
            track.strokeColor = Loop.cgColor(0x24324A)
            track.lineWidth = 2
            let arc = CAShapeLayer()
            arc.frame = CGRect(origin: .zero, size: s)
            arc.path = CGPath(ellipseIn: rect, transform: nil)
            arc.fillColor = nil
            arc.strokeColor = Loop.cgColor(0x3D8BFF)
            arc.lineWidth = 2
            arc.strokeEnd = 0.25
            root.addSublayer(track)
            root.addSublayer(arc)
            Loop.rotation(arc, period: 0.7)
        }
        .frame(width: size, height: size)
    }
}

/// Green live dot emitting a pulse (`mo-live 1.4s`).
struct LiveDot: View {
    var body: some View {
        LayerEffect { root, size in
            let pulse = CALayer()
            pulse.frame = CGRect(origin: .zero, size: size)
            pulse.cornerRadius = size.width / 2
            pulse.backgroundColor = Loop.cgColor(0x3DDC97, 0.6)
            let dot = CALayer()
            dot.frame = pulse.frame
            dot.cornerRadius = size.width / 2
            dot.backgroundColor = Loop.cgColor(0x3DDC97)
            root.addSublayer(pulse)
            root.addSublayer(dot)
            guard !Motion.reduce else { pulse.opacity = 0; return }
            let ease = CAMediaTimingFunction(name: .easeOut)
            pulse.add(Loop.basic("transform.scale", from: 1, to: 20.0 / 6, duration: 1.4, timing: ease), forKey: "s")
            pulse.add(Loop.basic("opacity", from: 1, to: 0, duration: 1.4, timing: ease), forKey: "o")
        }
        .frame(width: 6, height: 6)
    }
}
