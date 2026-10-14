import AppKit
import SwiftUI

/// Everything personal shown in the About window lives here.
enum AboutInfo {
    static let author = "Muh Ghazali Akbar"
    static let intro = "I build apps for macOS and the web. Digby started as a friendlier way to run Mole on my own Mac. If it frees up some space for you too, a coffee keeps it going."
    static let portfolio = URL(string: "https://justghali.dev")!
    static let github = URL(string: "https://github.com/muhghazaliakbar")!
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/muhghazaliakbar")!
    static let repository = URL(string: "https://github.com/muhghazaliakbar/digby")!
    static let mole = URL(string: "https://github.com/tw93/mole")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }
}

/// About window: the app, its author, links and a Buy Me a Coffee button.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            appHeader
                .padding(.top, 36)
                .padding(.bottom, 24)
            AuthorCard()
                .padding(.horizontal, 24)
                .rise(0.1)
            footer
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 22)
                .rise(0.2)
        }
        .frame(width: 440)
        .background {
            ZStack {
                DS.bgApp
                RadialGradient(colors: [DS.accent.opacity(0.18), .clear], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 320)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private var appHeader: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 104, height: 104)
                .shadow(color: DS.accent.opacity(0.35), radius: 24, y: 10)
                .pop(duration: 0.55, from: 0.8)
            VStack(spacing: 3) {
                Text("Digby").font(Fonts.ui(26, .bold)).tracking(-0.4).foregroundStyle(DS.textPrimary)
                Text(AboutInfo.version).font(Fonts.mono(11.5)).foregroundStyle(DS.textFaint)
                    .accessibilityIdentifier("about.version")
            }
            Text("A native macOS app for the open-source Mole CLI.")
                .font(Fonts.ui(13.5))
                .foregroundStyle(DS.textMuted)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                FooterLink(title: "Source on GitHub", url: AboutInfo.repository)
                Text("·").foregroundStyle(DS.textFaint)
                FooterLink(title: "MIT License", url: AboutInfo.repository.appendingPathComponent("blob/main/LICENSE"))
                Text("·").foregroundStyle(DS.textFaint)
                FooterLink(title: "Mole CLI", url: AboutInfo.mole)
            }
            .font(Fonts.ui(12))
            Text("Digby is an independent GUI for the open-source Mole CLI by tw93. Not affiliated with Mole or mole.fit. Fonts: Familjen Grotesk and JetBrains Mono (SIL OFL).")
                .font(Fonts.ui(11))
                .foregroundStyle(DS.textFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AuthorCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text("Made by").cardLabel(10.5)
                    Text(AboutInfo.author).font(Fonts.ui(17, .semibold)).foregroundStyle(DS.textPrimary)
                    Text(AboutInfo.portfolio.host() ?? "").font(Fonts.mono(11.5)).foregroundStyle(DS.accentLight)
                }
            }
            Text(AboutInfo.intro)
                .font(Fonts.ui(13.5))
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                LinkPill(title: "Portfolio", symbol: "globe", url: AboutInfo.portfolio)
                    .accessibilityIdentifier("about.portfolio")
                LinkPill(title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: AboutInfo.github)
                    .accessibilityIdentifier("about.github")
            }
            CoffeeButton()
                .accessibilityIdentifier("about.coffee")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(DS.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DS.border, lineWidth: 1))
    }

    @ViewBuilder private var avatar: some View {
        if let url = Bundle.main.url(forResource: "avatar", withExtension: "jpg"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        } else {
            Text("MG")
                .font(Fonts.ui(18, .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(DS.accent))
        }
    }
}

private struct LinkPill: View {
    let title: String
    let symbol: String
    let url: URL
    @State private var hovering = false

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(Fonts.ui(13, .medium))
                Text("↗").font(Fonts.ui(11)).foregroundStyle(DS.textFaint)
            }
            .foregroundStyle(hovering ? DS.textPrimary : DS.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(hovering ? DS.surfaceRaised : DS.bgApp))
            .overlay(Capsule().strokeBorder(hovering ? DS.borderHover : DS.border, lineWidth: 1))
            .offset(y: hovering ? -1 : 0)
        }
        .buttonStyle(PressStyle())
        .help(url.absoluteString)
        .onHover { h in withAnimation(Motion.easeOut(0.2)) { hovering = h } }
    }
}

/// Buy Me a Coffee in its brand yellow.
private struct CoffeeButton: View {
    @State private var hovering = false

    var body: some View {
        Link(destination: AboutInfo.buyMeACoffee) {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 14, weight: .semibold))
                Text("Buy me a coffee").font(Fonts.ui(14.5, .semibold))
            }
            .foregroundStyle(Color(hex: 0x0D0C22))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Capsule().fill(Color(hex: hovering ? 0xFFE433 : 0xFFDD00)))
            .shadow(color: Color(hex: 0xFFDD00).opacity(hovering ? 0.45 : 0.25), radius: hovering ? 14 : 10, y: 6)
            .offset(y: hovering ? -2 : 0)
        }
        .buttonStyle(PressStyle())
        .help(AboutInfo.buyMeACoffee.absoluteString)
        .onHover { h in withAnimation(Motion.overshoot(0.2, 1.6)) { hovering = h } }
    }
}

private struct FooterLink: View {
    let title: String
    let url: URL
    @State private var hovering = false

    var body: some View {
        Link(title, destination: url)
            .foregroundStyle(hovering ? DS.accentLight : DS.textMuted)
            .onHover { hovering = $0 }
    }
}

/// "About Digby" in the app menu plus support links in the Help menu.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Digby") {
                openWindow(id: "about")
                NSApp.activate()
            }
        }
        CommandGroup(replacing: .help) {
            Link("Digby on GitHub", destination: AboutInfo.repository)
            Link("Mole CLI", destination: AboutInfo.mole)
            Divider()
            Link("Buy Me a Coffee", destination: AboutInfo.buyMeACoffee)
        }
    }
}
