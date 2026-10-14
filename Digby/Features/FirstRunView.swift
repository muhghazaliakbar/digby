import AppKit
import SwiftUI

/// Shown when `mo` cannot be found: install with Homebrew, the official script, or locate the binary.
struct FirstRunView: View {
    @Environment(AppModel.self) private var app

    private let brew = "brew install mole"
    private let script = "curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash"

    var body: some View {
        VStack(spacing: 26) {
            Text("dg")
                .font(Fonts.mono(26, .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 16).fill(DS.accent))
                .shadow(color: DS.accent.opacity(0.8), radius: 18, y: 12)
                .pop(0.05)

            VStack(spacing: 8) {
                Text("Install the Mole CLI").font(Fonts.ui(28, .semibold)).tracking(-0.4)
                Text("Digby is a front-end for the open-source mo command. Install it once, then come back here. Nothing on your Mac is touched until you review it.")
                    .font(Fonts.ui(14.5))
                    .foregroundStyle(DS.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 520)
            }
            .rise(0.1)

            VStack(spacing: 10) {
                CommandRow(label: "Homebrew", command: brew).rise(0.18)
                CommandRow(label: "Install script", command: script).rise(0.24)
            }
            .frame(maxWidth: 620)

            HStack(spacing: 10) {
                Button("Locate binary…", action: locate)
                    .buttonStyle(PillButtonStyle(kind: .secondary, height: 42, fontSize: 15))
                Button("Check again") { app.recheckBinary() }
                    .buttonStyle(PillButtonStyle(kind: .primary, height: 42, fontSize: 15))
            }
            .rise(0.3)

            Text("Digby is an independent GUI for the open-source Mole CLI by tw93. Not affiliated with Mole or mole.fit.")
                .font(Fonts.ui(12))
                .foregroundStyle(DS.textFaint)
                .rise(0.36)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func locate() {
        let panel = NSOpenPanel()
        panel.title = "Locate the mo binary"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            app.useBinary(at: url)
        }
    }
}

private struct CommandRow: View {
    let label: String
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(Fonts.ui(12.5, .semibold)).foregroundStyle(DS.textMuted).frame(width: 96, alignment: .leading)
            HStack(spacing: 8) {
                Text("$").foregroundStyle(DS.accent)
                Text(command).foregroundStyle(DS.textSecondary).lineLimit(1).truncationMode(.middle)
            }
            .font(Fonts.mono(12.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .milliseconds(1400))
                    copied = false
                }
            } label: {
                Text(copied ? "copied ✓" : "copy")
                    .font(Fonts.mono(11.5))
                    .foregroundStyle(copied ? DS.success : DS.textFaint)
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(DS.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(copied ? Color(hex: 0x1D4434) : DS.border, lineWidth: 1))
        .animation(.easeOut(duration: 0.25), value: copied)
    }
}
