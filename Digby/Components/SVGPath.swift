import SwiftUI

/// Minimal SVG path-data parser (M/L/H/V/Z, absolute and relative) for the design's 24×24 icons.
nonisolated struct SVGPath: Shape {
    let data: String
    var viewBox: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        let origin = CGPoint(x: rect.midX - viewBox * scale / 2, y: rect.midY - viewBox * scale / 2)
        return Self.parse(data).applying(CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale))
    }

    static func parse(_ d: String) -> Path {
        var path = Path()
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch == "-" && !current.isEmpty && !current.hasSuffix("e") {
                tokens.append(current); current = "-"
            } else if ch == "." && current.contains(".") {
                tokens.append(current); current = "."
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var i = 0
        var cmd: Character = "M"
        var pt = CGPoint.zero
        var start = CGPoint.zero
        func num() -> CGFloat {
            defer { i += 1 }
            return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0
        }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter {
                cmd = c
                i += 1
                if c == "z" || c == "Z" {
                    path.closeSubpath()
                    pt = start
                    continue
                }
            }
            switch cmd {
            case "M":
                pt = CGPoint(x: num(), y: num()); path.move(to: pt); start = pt; cmd = "L"
            case "m":
                pt = CGPoint(x: pt.x + num(), y: pt.y + num()); path.move(to: pt); start = pt; cmd = "l"
            case "L":
                pt = CGPoint(x: num(), y: num()); path.addLine(to: pt)
            case "l":
                pt = CGPoint(x: pt.x + num(), y: pt.y + num()); path.addLine(to: pt)
            case "H":
                pt.x = num(); path.addLine(to: pt)
            case "h":
                pt.x += num(); path.addLine(to: pt)
            case "V":
                pt.y = num(); path.addLine(to: pt)
            case "v":
                pt.y += num(); path.addLine(to: pt)
            default:
                i += 1
            }
        }
        return path
    }
}

/// A design icon: 1.7 stroke, round caps and joins.
struct StrokeIcon: View {
    let data: String
    var size: CGFloat = 17
    var lineWidth: CGFloat = 1.7

    var body: some View {
        SVGPath(data: data)
            .stroke(style: StrokeStyle(lineWidth: lineWidth * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}
