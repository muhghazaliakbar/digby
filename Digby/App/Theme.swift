import AppKit
import CoreText
import SwiftUI

// MARK: - Colors

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Design tokens from the handoff (PROMPT.md · "Design tokens").
enum DS {
    static let bgApp = Color(hex: 0x0E1013)
    static let bgSidebar = Color(hex: 0x0A0B0E)
    static let bgDrawer = Color(hex: 0x08090B)
    static let bgFooter = Color(hex: 0x0C0D10)
    static let bgDisk = Color(hex: 0x111318)
    static let surface = Color(hex: 0x14171C)
    static let surfaceHover = Color(hex: 0x171A20)
    static let surfaceRaised = Color(hex: 0x1A1E24)
    static let surfaceTrack = Color(hex: 0x1C2027)
    static let sparkBg = Color(hex: 0x171A20)
    static let border = Color(hex: 0x22262D)
    static let borderHover = Color(hex: 0x2E343D)
    static let borderSubtle = Color(hex: 0x1C1F25)
    static let borderSubtle2 = Color(hex: 0x1E2229)
    static let borderStrong = Color(hex: 0x2A2F37)
    static let borderMuted = Color(hex: 0x3A404A)
    static let textPrimary = Color(hex: 0xE8EAED)
    static let textSecondary = Color(hex: 0xB8BEC7)
    static let textMuted = Color(hex: 0x8A919C)
    static let textFaint = Color(hex: 0x5D6470)
    static let navIdle = Color(hex: 0x9AA1AC)
    static let accent = Color(hex: 0x3D8BFF)
    static let accentHover = Color(hex: 0x5A9CFF)
    static let accentLight = Color(hex: 0x7AB0FF)
    static let accentSelection = Color(hex: 0x16243A)
    static let success = Color(hex: 0x3DDC97)
    static let warning = Color(hex: 0xFFB547)
    static let danger = Color(hex: 0xFF5C5C)
    static let dangerHover = Color(hex: 0xFF7373)
    static let violet = Color(hex: 0x7C6CFF)
    static let cyan = Color(hex: 0x2BC4E8)
    static let orange = Color(hex: 0xFF7A59)
    static let pink = Color(hex: 0xE86BB0)
    static let slate = Color(hex: 0x9AA4B2)

    /// Category palette order (rings, treemap).
    static let palette: [Color] = [accent, violet, cyan, success, warning, orange, pink, slate]
    static let paletteHex: [UInt32] = [0x3D8BFF, 0x7C6CFF, 0x2BC4E8, 0x3DDC97, 0xFFB547, 0xFF7A59, 0xE86BB0, 0x9AA4B2]

    static let sidebarWidth: CGFloat = 228
}

// MARK: - Fonts

enum Fonts {
    static let uiFamily = "Familjen Grotesk"
    static let monoFamily = "JetBrains Mono"

    /// Registers the bundled OFL fonts for this process. Falls back to SF Pro / SF Mono when missing.
    static func register() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(uiFamily, size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(monoFamily, size: size).weight(weight)
    }
}

extension View {
    /// Card label: 11.5 / 600, uppercase, +0.08em tracking.
    func cardLabel(_ size: CGFloat = 11.5) -> some View {
        font(Fonts.ui(size, .semibold))
            .tracking(size * 0.08)
            .textCase(.uppercase)
            .foregroundStyle(DS.textMuted)
    }
}

// MARK: - Motion

enum Motion {
    /// `cubic-bezier(.2,.8,.2,1)` — the design's default ease-out.
    static func easeOut(_ duration: Double) -> Animation {
        reduce ? .easeOut(duration: min(duration, 0.15)) : .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
    }

    /// `cubic-bezier(.3,1.3,.5,1)`-style overshooting curves.
    static func overshoot(_ duration: Double, _ y1: Double = 1.3) -> Animation {
        reduce ? .easeOut(duration: min(duration, 0.15)) : .timingCurve(0.3, y1, 0.5, 1, duration: duration)
    }

    /// `cubic-bezier(.5,0,.75,0)` — ease-in used for exits.
    static func easeIn(_ duration: Double) -> Animation {
        reduce ? .easeOut(duration: min(duration, 0.15)) : .timingCurve(0.5, 0, 0.75, 0, duration: duration)
    }

    static func spring(_ response: Double, _ damping: Double) -> Animation {
        reduce ? .easeOut(duration: 0.15) : .spring(response: response, dampingFraction: damping)
    }

    /// Sidebar highlight: response 0.5, damping 0.7.
    static var nav: Animation { spring(0.5, 0.7) }
    /// Checkbox / toggle knob: response 0.35, damping 0.55.
    static var bouncy: Animation { spring(0.35, 0.55) }
    /// Number count-ups: easeOutCubic.
    static func count(_ duration: Double) -> Animation {
        reduce ? .easeOut(duration: 0.15) : .timingCurve(0.33, 1, 0.68, 1, duration: duration)
    }

    static func stagger(_ index: Int, step: Double = 0.035, base: Double = 0) -> Double {
        reduce ? 0 : base + Double(min(index, 14)) * step
    }

    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

// MARK: - Formatting

nonisolated enum Fmt {
    /// Mirrors the design's `fmt()` with decimal units, as Finder reports them.
    static func size(_ bytes: Double) -> String {
        guard bytes > 0.5 else { return "0 KB" }
        let g = bytes / 1_000_000_000
        if g >= 1 { return g >= 100 ? String(format: "%.0f GB", g) : String(format: "%.1f GB", g) }
        let m = bytes / 1_000_000
        if m >= 1 { return m >= 100 ? String(format: "%.0f MB", m) : String(format: "%.1f MB", m) }
        return "\(max(1, Int((bytes / 1000).rounded()))) KB"
    }


    static func rate(_ mbPerSec: Double) -> String {
        mbPerSec >= 1 ? String(format: "%.1f MB/s", mbPerSec) : "\(Int((mbPerSec * 1024).rounded())) KB/s"
    }

    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Never" }
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "\(days) days ago"
        case 7..<14: return "1 week ago"
        case 14..<30: return "\(days / 7) weeks ago"
        case 30..<60: return "1 month ago"
        case 60..<365: return "\(days / 30) months ago"
        case 365..<730: return "1 year ago"
        default: return "\(days / 365) years ago"
        }
    }

    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func tildePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func expandTilde(_ path: String) -> String {
        path.hasPrefix("~") ? NSHomeDirectory() + path.dropFirst() : path
    }
}
