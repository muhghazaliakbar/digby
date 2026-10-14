import AppKit
import Foundation
import Observation
import SwiftUI

@Observable
final class UninstallModel {
    enum Sort: String, CaseIterable { case size = "Largest", name = "Name", used = "Least used" }
    enum Phase { case idle, removing, closing }

    struct Leftover: Identifiable, Equatable {
        var id: String { path }
        let path: String
        let bytes: Double
    }

    struct AppEntry: Identifiable, Equatable {
        var id: String { path }
        let path: String
        let name: String
        let bundleID: String
        var version: String = ""
        var lastUsed: Date?
        var bundleBytes: Double = 0
        var leftovers: [Leftover] = []
        var measured = false

        var total: Double { bundleBytes + leftovers.reduce(0) { $0 + $1.bytes } }
    }

    @ObservationIgnored unowned let app: AppModel
    var apps: [AppEntry] = []
    var loaded = false
    var loading = false
    var query = ""
    var sort: Sort = .size
    var selectedID: String?
    var selectionChanges = 0
    var unchecked: Set<String> = []
    var phase: Phase = .idle
    var step = -1
    var steps: [String] = []
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    init(app: AppModel) { self.app = app }

    // MARK: Derived

    var visible: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = apps.filter { q.isEmpty || $0.name.lowercased().contains(q) }
        switch sort {
        case .size: return list.sorted { $0.total > $1.total }
        case .name: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .used: return list.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    var current: AppEntry? {
        let list = visible
        return list.first { $0.id == selectedID } ?? list.first
    }

    func total(for entry: AppEntry) -> Double {
        entry.bundleBytes + entry.leftovers.filter { !unchecked.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }

    func icon(for entry: AppEntry) -> NSImage {
        if let cached = icons[entry.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: entry.path)
        icons[entry.path] = image
        return image
    }

    func select(_ entry: AppEntry) {
        guard phase == .idle, entry.id != current?.id else { return }
        selectedID = entry.id
        selectionChanges += 1
    }

    func toggle(_ leftover: Leftover) {
        guard phase == .idle else { return }
        if unchecked.contains(leftover.path) { unchecked.remove(leftover.path) } else { unchecked.insert(leftover.path) }
    }

    // MARK: Loading

    func loadIfNeeded() {
        if !loaded && !loading { reload() }
    }

    func reload() {
        guard !loading, phase == .idle else { return }
        loading = true
        app.terminal.log("mo uninstall --list", .cmd)
        Task { await load() }
    }

    private func load() async {
        var listed: [ListedApp] = []
        if let (data, _) = try? await MoleRunner.shared.captureData(["uninstall", "--list"]) {
            listed = ListedApp.decodeList(data)
        }
        if listed.isEmpty {
            app.terminal.log("Falling back to scanning /Applications", .dim)
            listed = await Task.detached { AppScanner.scanApplications() }.value
        }
        app.terminal.log("\(listed.count) apps found", .ok)
        var entries = listed
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { AppEntry(path: $0.path, name: $0.name, bundleID: $0.bundle_id ?? "") }
        for i in entries.indices {
            let info = AppScanner.info(at: entries[i].path)
            entries[i].version = info.version
            entries[i].lastUsed = info.lastUsed
        }
        withAnimation(Motion.easeOut(0.4)) {
            apps = entries
            loaded = true
            loading = false
        }
        await measureAll()
    }

    /// Sizes bundles and finds leftovers off the main thread, a few apps at a time.
    private func measureAll() async {
        let targets = apps.map { ($0.path, $0.name, $0.bundleID) }
        await withTaskGroup(of: (String, Double, [Leftover]).self) { group in
            var iterator = targets.makeIterator()
            func addNext() {
                guard let (path, name, bundle) = iterator.next() else { return }
                group.addTask {
                    let size = FileInfo.allocatedSize(path)
                    let leftovers = AppScanner.leftovers(name: name, bundleID: bundle).map { Leftover(path: $0.0, bytes: $0.1) }
                    return (path, size, leftovers)
                }
            }
            for _ in 0..<4 { addNext() }
            while let (path, size, leftovers) = await group.next() {
                if let i = apps.firstIndex(where: { $0.path == path }) {
                    withAnimation(Motion.easeOut(0.35)) {
                        apps[i].bundleBytes = size
                        apps[i].leftovers = leftovers
                        apps[i].measured = true
                    }
                }
                addNext()
            }
        }
    }

    // MARK: Uninstall

    func uninstall() {
        guard phase == .idle, let target = current else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first, !target.bundleID.isEmpty {
            app.toast("Quit \(target.name) first", "It is still running", color: DS.warning)
            app.terminal.log("\(target.name) is running (pid \(running.processIdentifier)); quit it before uninstalling", .warn)
            return
        }
        let leftovers = target.leftovers.filter { !unchecked.contains($0.path) }
        selectedID = target.id
        steps = ["bundle"] + leftovers.map(\.path)
        step = -1
        withAnimation { phase = .removing }
        Task { await remove(target, leftovers: leftovers) }
    }

    private func remove(_ target: AppEntry, leftovers: [Leftover]) async {
        app.terminal.log("mo uninstall \"\(target.name)\"  · moving to Trash", .cmd)
        let files = [target.path] + leftovers.map(\.path)
        try? await Task.sleep(for: .milliseconds(150))
        var failed = false
        for (i, path) in files.enumerated() {
            let started = Date()
            if await Trash.move(path) {
                app.terminal.log("→ Trash  \(Fmt.tildePath(path))")
            } else {
                app.terminal.log("Could not move \(Fmt.tildePath(path)) to the Trash", .warn)
                if i == 0 { failed = true; break }
            }
            withAnimation(Motion.overshoot(0.45, 1.3)) { step = i }
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.23 { try? await Task.sleep(for: .milliseconds(Int((0.23 - elapsed) * 1000))) }
        }
        if failed {
            app.toast("Could not remove \(target.name)", "The app bundle stayed in place", color: DS.danger)
            withAnimation { phase = .idle; step = -1; steps = [] }
            return
        }
        try? await Task.sleep(for: .milliseconds(260))
        withAnimation(Motion.easeIn(0.5)) { phase = .closing }
        try? await Task.sleep(for: .milliseconds(520))
        let total = target.bundleBytes + leftovers.reduce(0) { $0 + $1.bytes }
        app.terminal.log("\(target.name) removed · \(Fmt.size(total)) moved to Trash", .ok)
        app.toast("\(target.name) removed", "\(Fmt.size(total)) moved to Trash")
        app.disk.refreshAfterAction()
        withAnimation(Motion.easeOut(0.45)) {
            apps.removeAll { $0.id == target.id }
            phase = .idle
            step = -1
            steps = []
            selectedID = visible.first?.id
            selectionChanges += 1
        }
    }
}

/// Native app inventory helpers (metadata Mole's `--list` does not include).
nonisolated enum AppScanner {
    static func scanApplications() -> [ListedApp] {
        let roots = ["/Applications", NSHomeDirectory() + "/Applications"]
        var result: [ListedApp] = []
        for root in roots {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for name in names where name.hasSuffix(".app") {
                let path = root + "/" + name
                let bundle = Bundle(path: path)
                let display = (bundle?.infoDictionary?["CFBundleDisplayName"] as? String) ?? String(name.dropLast(4))
                result.append(ListedApp(name: display, bundle_id: bundle?.bundleIdentifier, source: "App", uninstall_name: display, path: path))
            }
        }
        return result
    }

    static func info(at path: String) -> (version: String, lastUsed: Date?) {
        let version = Bundle(path: path)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        var lastUsed: Date?
        if let item = MDItemCreate(nil, path as CFString),
           let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            lastUsed = date
        }
        return (version, lastUsed)
    }

    /// Finds files an app leaves behind in the user Library, matched by bundle ID or app name.
    static func leftovers(name: String, bundleID: String) -> [(String, Double)] {
        let fm = FileManager.default
        let lib = NSHomeDirectory() + "/Library"
        var paths: [String] = []
        func add(_ p: String) { if fm.fileExists(atPath: p) && !paths.contains(p) { paths.append(p) } }

        if !bundleID.isEmpty {
            for dir in ["Application Support", "Caches", "Containers", "Logs", "HTTPStorages", "WebKit", "Application Scripts"] {
                add("\(lib)/\(dir)/\(bundleID)")
            }
            add("\(lib)/Preferences/\(bundleID).plist")
            add("\(lib)/Saved Application State/\(bundleID).savedState")
            add("\(lib)/Cookies/\(bundleID).binarycookies")
            add("\(lib)/HTTPStorages/\(bundleID).binarycookies")
            for dir in ["Group Containers", "LaunchAgents", "Preferences/ByHost"] {
                let base = "\(lib)/\(dir)"
                for entry in (try? fm.contentsOfDirectory(atPath: base)) ?? [] where entry.contains(bundleID) {
                    add("\(base)/\(entry)")
                }
            }
        }
        let safeName = name.trimmingCharacters(in: .whitespaces)
        if safeName.count >= 3 {
            for dir in ["Application Support", "Caches", "Logs"] { add("\(lib)/\(dir)/\(safeName)") }
        }
        return paths.map { ($0, FileInfo.allocatedSize($0)) }.sorted { $0.1 > $1.1 }
    }

    @MainActor static func kind(of path: String) -> (String, Color) {
        if path.contains("LaunchAgents") || path.contains("LaunchDaemons") { return ("Launch item", DS.warning) }
        if path.contains("Caches") { return ("Cache", DS.accent) }
        if path.contains("Preferences") { return ("Prefs", DS.cyan) }
        if path.contains("Containers") { return ("Container", DS.violet) }
        if path.contains("Logs") { return ("Logs", DS.success) }
        if path.contains("Saved Application") { return ("State", DS.slate) }
        return ("Support", DS.pink)
    }
}
