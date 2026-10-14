// Renders Digby's app icon: the segmented "Clean" ring in the category palette,
// around a "dg" monogram, on a dark macOS squircle.
//
//   swift scripts/make-icon.swift
//
// Writes every size into Digby/Assets.xcassets/AppIcon.appiconset and docs/icon.png.
import AppKit
import CoreText

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let fontURL = root.appendingPathComponent("Digby/Resources/Fonts/JetBrainsMono.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Apple-style continuous-corner squircle (superellipse, n = 5).
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath()
    let n = 5.0, steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * CGFloat(copysign(pow(abs(c), 2 / n), c))
        let y = r.midY + r.height / 2 * CGFloat(copysign(pow(abs(s), 2 / n), s))
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px) / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    ctx.setShouldAntialias(true)

    // Body on the macOS icon grid: 824 pt with a 100 pt margin, soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0x000000, 0.45))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x0E1013)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    // Background: deep navy at the top fading to near-black.
    let bg = CGGradient(colorsSpace: nil, colors: [rgb(0x1B2433), rgb(0x0E1117), rgb(0x090A0D)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Accent glow behind the ring.
    let glow = CGGradient(colorsSpace: nil, colors: [rgb(0x3D8BFF, 0.42), rgb(0x3D8BFF, 0.10), rgb(0x3D8BFF, 0)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 500), startRadius: 0, endCenter: CGPoint(x: 512, y: 500), endRadius: 420, options: [])

    // Segmented ring: palette segments clockwise from 12 o'clock, then the track.
    let center = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 268, thickness: CGFloat = 74
    // Degrees per category, multiples of the 6° tick so colour changes land on a gap.
    let segments: [(UInt32, Double)] = [(0x3D8BFF, 90), (0x7C6CFF, 54), (0x2BC4E8, 48), (0x3DDC97, 60), (0xFFB547, 30), (0xFF7A59, 18)]
    let small = px <= 64
    let tick = 6.0, gap = small ? 0 : 1.6
    var angle = 0.0
    func arc(from a0: Double, to a1: Double, color: CGColor) {
        var a = a0
        while a < a1 - 0.01 {
            let next = min(a1, (floor(a / tick) + 1) * tick)
            let end = next - (next.truncatingRemainder(dividingBy: tick) == 0 ? gap : 0)
            if end > a {
                // Degrees clockwise from 12 o'clock → CoreGraphics radians.
                let start = CGFloat((90 - a) * .pi / 180), stop = CGFloat((90 - end) * .pi / 180)
                let p = CGMutablePath()
                p.addArc(center: center, radius: radius, startAngle: start, endAngle: stop, clockwise: true)
                ctx.addPath(p)
                ctx.setStrokeColor(color)
                ctx.setLineWidth(thickness)
                ctx.setLineCap(.butt)
                ctx.strokePath()
            }
            a = next
        }
    }
    for (hex, degrees) in segments {
        let end = angle + degrees
        ctx.saveGState()
        if !small { ctx.setShadow(offset: .zero, blur: 18, color: rgb(hex, 0.55)) }
        arc(from: angle, to: end, color: rgb(hex))
        ctx.restoreGState()
        angle = end
    }
    arc(from: angle, to: 360, color: rgb(0x252B36))

    // Inner disc, like the ring centre in the app.
    let inner = radius - thickness / 2 - 18
    let disc = CGGradient(colorsSpace: nil, colors: [rgb(0x1A1F28), rgb(0x0E1013)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
    ctx.clip()
    ctx.drawRadialGradient(disc, startCenter: CGPoint(x: 512, y: 600), startRadius: 0, endCenter: center, endRadius: inner * 1.15, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    ctx.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.07)); ctx.setLineWidth(3); ctx.strokePath()

    // "dg" monogram.
    let font = CTFontCreateWithName("JetBrains Mono" as CFString, 200, nil)
    let bold = CTFontCreateCopyWithAttributes(font, 200, nil,
        CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: [0x77676874: 700]] as CFDictionary))
    let attrs: [NSAttributedString.Key: Any] = [.font: bold, .foregroundColor: rgb(0xF2F5F9), .kern: -10]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "dg", attributes: attrs))
    let bounds = CTLineGetImageBounds(line, ctx)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 20, color: rgb(0x000000, 0.5))
    ctx.textPosition = CGPoint(x: center.x - bounds.width / 2 - bounds.minX, y: center.y - bounds.height / 2 - bounds.minY - 4)
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    // Top sheen and hairline edge.
    let sheen = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
    ctx.restoreGState()
    ctx.addPath(shape); ctx.setStrokeColor(rgb(0xFFFFFF, 0.10)); ctx.setLineWidth(2.5); ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let set = root.appendingPathComponent("Digby/Assets.xcassets/AppIcon.appiconset")
for (size, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    try! render(size * scale).write(to: set.appendingPathComponent(name))
}
try! render(512).write(to: root.appendingPathComponent("docs/icon.png"))
print("Icon written to \(set.path)")
