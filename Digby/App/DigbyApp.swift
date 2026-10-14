import AppKit
import SwiftUI

@main
struct DigbyApp: App {
    @State private var app = AppModel()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("menuBarShowsFree") private var menuBarShowsFree = true

    init() {
        Fonts.register()
    }

    var body: some Scene {
        Window("Digby", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 1080, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 820)
        .commands {
            AboutCommands()
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Modules") {
                ForEach(Module.allCases) { module in
                    Button(module.title) { withAnimation(Motion.nav) { app.go(module) } }
                        .keyboardShortcut(KeyEquivalent(Character("\(module.index + 1)")), modifiers: .command)
                }
            }
            CommandGroup(after: .toolbar) {
                Button(app.termOpen ? "Hide Terminal" : "Show Terminal") { app.toggleTerminal() }
                    .keyboardShortcut("j", modifiers: .command)
                Button("Rescan") { app.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Cancel Running Job") { app.cancelRunningJob() }
                    .keyboardShortcut(.escape, modifiers: [])
                Divider()
                Toggle("Show in Menu Bar", isOn: $showMenuBarExtra)
                Toggle("Show Free Space in Menu Bar", isOn: $menuBarShowsFree)
                    .disabled(!showMenuBarExtra)
                Divider()
            }
        }

        Window("About Digby", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarPanel()
                .environment(app)
        } label: {
            MenuBarLabel(disk: app.disk, showsFree: menuBarShowsFree)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            VStack(spacing: 0) {
                HeaderBar()
                ZStack {
                    content
                    ToastStack()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                TerminalDrawer()
                    .frame(height: app.termOpen ? 210 : 0, alignment: .top)
                    .clipped()
                    .overlay(alignment: .top) {
                        Rectangle().fill(app.termOpen ? DS.borderSubtle : .clear).frame(height: 1)
                    }
                    .animation(Motion.easeOut(0.42), value: app.termOpen)
            }
            .background(DS.bgApp)
        }
        .background(DS.bgApp)
        .ignoresSafeArea()
        .background(WindowConfigurator())
        .onAppear { app.start() }
    }

    @ViewBuilder private var content: some View {
        if !app.moAvailable {
            FirstRunView().id("first-run").pageEnter()
        } else {
            Group {
                switch app.view {
                case .status: StatusView(model: app.status)
                case .clean: CleanView(model: app.clean)
                case .uninstall: UninstallView(model: app.uninstall)
                case .optimize: OptimizeView(model: app.optimize)
                case .purge: ListView(model: app.purge)
                case .installers: ListView(model: app.installers)
                case .analyze: AnalyzeView(model: app.analyze)
                }
            }
            .id(app.view)
        }
    }
}

/// Hidden title bar, full-size content, traffic lights inset 16 px into the sidebar.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = TrafficLightView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrafficLightView: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = NSColor(red: 0x0E / 255, green: 0x10 / 255, blue: 0x13 / 255, alpha: 1)
            window.appearance = NSAppearance(named: .darkAqua)
            for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.layoutButtons() }
                })
            }
            DispatchQueue.main.async { self.layoutButtons() }
        }

        override func layout() {
            super.layout()
            layoutButtons()
        }

        /// Design: lights at x = 18 (sidebar padding 12 + 6), y = 16, 20 px apart.
        private func layoutButtons() {
            guard let window, !window.styleMask.contains(.fullScreen),
                  let titlebar = window.standardWindowButton(.closeButton)?.superview,
                  let container = titlebar.superview, let theme = container.superview else { return }
            // Make the transparent title bar tall enough to hold the lights 16 px from the top.
            let desired: CGFloat = 44
            if container.frame.height != desired {
                container.frame = NSRect(x: 0, y: theme.frame.height - desired, width: theme.frame.width, height: desired)
            }
            if titlebar.frame.height != desired {
                titlebar.frame = container.bounds
            }
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (i, type) in types.enumerated() {
                guard let button = window.standardWindowButton(type) else { continue }
                let y = titlebar.isFlipped ? 15 : titlebar.frame.height - 15 - button.frame.height
                button.setFrameOrigin(NSPoint(x: 17 + CGFloat(i) * 20, y: y))
            }
        }
    }
}
