import AppKit
import Observation
import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case status, clean, uninstall, optimize, purge, installers, analyze

    var id: String { rawValue }
    var index: Int { Module.allCases.firstIndex(of: self)! }

    var title: String {
        switch self {
        case .status: "Status"
        case .clean: "Clean"
        case .uninstall: "Uninstall"
        case .optimize: "Optimize"
        case .purge: "Purge"
        case .installers: "Installers"
        case .analyze: "Analyze"
        }
    }

    var subtitle: String {
        switch self {
        case .status: "Live health of this Mac"
        case .clean: "Caches, logs and leftovers"
        case .uninstall: "Remove apps and everything they left behind"
        case .optimize: "Rebuild caches and refresh system services"
        case .purge: "Build artifacts in your projects"
        case .installers: "Disk images and packages you no longer need"
        case .analyze: "See what is taking up space"
        }
    }

    var command: String {
        switch self {
        case .status: "mo status"
        case .clean: "mo clean"
        case .uninstall: "mo uninstall"
        case .optimize: "mo optimize"
        case .purge: "mo purge"
        case .installers: "mo installer"
        case .analyze: "mo analyze ~"
        }
    }

    /// 24×24 stroke icons from the design.
    var icon: String {
        switch self {
        case .status: "M3 12h4l3-8 4 16 3-8h4"
        case .clean: "M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5L18 18M6 18l2.5-2.5M15.5 8.5L18 6"
        case .uninstall: "M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v5M14 11v5"
        case .optimize: "M13 3L5 14h6l-1 7 8-11h-6l1-7z"
        case .analyze: "M3 4h18v16H3zM12 4v16M12 12h9M16 12v8"
        case .purge: "M3 7l9-4 9 4-9 4-9-4zM3 12l9 4 9-4M3 17l9 4 9-4"
        case .installers: "M12 3v12M7 10l5 5 5-5M4 20h16"
        }
    }

    static let groups: [(String, [Module])] = [
        ("Overview", [.status]),
        ("Maintain", [.clean, .uninstall, .optimize, .purge, .installers]),
        ("Inspect", [.analyze]),
    ]
}

struct Toast: Identifiable, Equatable {
    let id: Int
    let title: String
    let subtitle: String
    let color: Color
    var leaving = false
}

@Observable
final class AppModel {
    var view: Module = .clean
    /// Increments on each page change so header animations alternate.
    private(set) var viewChanges = 0
    var termOpen = false
    var copied = false
    private(set) var toasts: [Toast] = []
    private var toastID = 0
    private var copyTask: Task<Void, Never>?

    var moAvailable: Bool = MoleRunner.locate() != nil
    var moVersion: String = ""

    let terminal = TerminalLog()
    let disk = DiskInfo()

    @ObservationIgnored lazy var status = StatusModel(app: self)
    @ObservationIgnored lazy var clean = CleanModel(app: self)
    @ObservationIgnored lazy var uninstall = UninstallModel(app: self)
    @ObservationIgnored lazy var optimize = OptimizeModel(app: self)
    @ObservationIgnored lazy var purge = ListModel(app: self, kind: .purge)
    @ObservationIgnored lazy var installers = ListModel(app: self, kind: .installers)
    @ObservationIgnored lazy var analyze = AnalyzeModel(app: self)

    init() {
        WhitelistGuard.restoreIfNeeded()
        // Launch arguments, like the design's props: `-startView status -showTerminal YES`.
        let defaults = UserDefaults.standard
        if let start = defaults.string(forKey: "startView"), let module = Module(rawValue: start.lowercased()) { view = module }
        termOpen = defaults.bool(forKey: "showTerminal")
    }

    func start() {
        Task { await loadVersion() }
        if moAvailable { onEnter(view) }
        #if DEBUG
        // Debug-only hook for automated checks: `-autoScan YES` starts a Clean dry-run scan.
        if moAvailable && UserDefaults.standard.bool(forKey: "autoScan") { clean.startScan() }
        #endif
    }

    func go(_ module: Module) {
        guard module != view else { return }
        if view == .status { status.stop() }
        view = module
        viewChanges += 1
        onEnter(module)
    }

    func onEnter(_ module: Module) {
        guard moAvailable else { return }
        switch module {
        case .status: status.start()
        case .uninstall: uninstall.loadIfNeeded()
        case .optimize: optimize.loadIfNeeded()
        case .purge: purge.scanIfNeeded()
        case .installers: installers.scanIfNeeded()
        case .analyze: analyze.loadIfNeeded()
        case .clean: break
        }
    }

    /// The header command for the current module (Clean reflects the dry-run toggle).
    var command: String {
        if view == .clean && clean.dryRun { return "mo clean --dry-run" }
        if view == .analyze { return "mo analyze " + analyze.displayPath }
        return view.command
    }

    func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
        copyTask?.cancel()
        copyTask = Task {
            try? await Task.sleep(for: .milliseconds(1400))
            if !Task.isCancelled { copied = false }
        }
    }

    func toggleTerminal() { termOpen.toggle() }

    /// Bottom-right toast with a 3.5 s countdown. Max 3 stacked.
    func toast(_ title: String, _ subtitle: String, color: Color = DS.success) {
        toastID += 1
        let id = toastID
        withAnimation(Motion.spring(0.5, 0.72)) {
            toasts = Array(toasts.suffix(2)) + [Toast(id: id, title: title, subtitle: subtitle, color: color)]
        }
        Task {
            try? await Task.sleep(for: .milliseconds(3500))
            withAnimation(Motion.easeIn(0.35)) {
                if let i = toasts.firstIndex(where: { $0.id == id }) { toasts[i].leaving = true }
            }
            try? await Task.sleep(for: .milliseconds(400))
            toasts.removeAll { $0.id == id }
        }
    }

    // MARK: Keyboard

    func rescan() {
        guard moAvailable else { return }
        switch view {
        case .status: status.restart()
        case .clean: clean.startScan()
        case .uninstall: uninstall.reload()
        case .optimize: optimize.reload()
        case .purge: purge.scan()
        case .installers: installers.scan()
        case .analyze: analyze.rescan()
        }
    }

    func cancelRunningJob() {
        switch view {
        case .clean: clean.cancel()
        case .optimize: optimize.cancel()
        case .purge: purge.cancel()
        case .installers: installers.cancel()
        case .analyze: analyze.cancel()
        default: break
        }
    }

    // MARK: Mole binary

    func loadVersion() async {
        guard moAvailable else { return }
        terminal.log("mo --version", .cmd)
        if let (out, _) = try? await MoleRunner.shared.capture(["--version"]) {
            let lines = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let version = lines.first(where: { $0.lowercased().hasPrefix("mole version") }).map { String($0.dropFirst("Mole version".count)).trimmingCharacters(in: .whitespaces) } ?? ""
            moVersion = version
            let os = lines.first(where: { $0.hasPrefix("macOS:") })?.dropFirst(6).trimmingCharacters(in: .whitespaces) ?? ""
            let arch = lines.first(where: { $0.hasPrefix("Architecture:") })?.dropFirst(13).trimmingCharacters(in: .whitespaces) ?? ""
            terminal.log("Mole \(version) · macOS \(os) · \(arch) · \(Fmt.size(disk.total)) APFS", .dim)
        }
    }

    func useBinary(at url: URL) {
        UserDefaults.standard.set(url.path, forKey: MoleRunner.pathDefaultsKey)
        recheckBinary()
    }

    func recheckBinary() {
        let found = MoleRunner.locate() != nil
        withAnimation(Motion.easeOut(0.45)) { moAvailable = found }
        if found { start(); onEnter(view) }
    }
}
