import Foundation
import Observation
import SwiftUI

/// Shared model for Purge (`mo purge`) and Installers (`mo installer`).
@Observable
final class ListModel {
    enum Kind { case purge, installers }
    enum Phase { case idle, scanning, ready, working, done }

    struct Entry: Identifiable, Equatable {
        let id: String
        let path: String
        let tag: String
        let name: String
        let sub: String
        let bytes: Double
        let recent: Bool
    }

    @ObservationIgnored unowned let app: AppModel
    let kind: Kind
    var phase: Phase = .idle
    var entries: [Entry] = []
    var selected: Set<String> = []
    var removed: Set<String> = []
    var gone: Set<String> = []
    var doneCount = 0
    var totalCount = 0
    var freed: Double = 0
    var freedCount = 0
    var scanned = false

    @ObservationIgnored private var process: MoleProcess?
    @ObservationIgnored private var cancelled = false

    init(app: AppModel, kind: Kind) {
        self.app = app
        self.kind = kind
    }

    var verb: String { kind == .purge ? "Purge" : "Remove" }
    var command: [String] { kind == .purge ? ["purge", "--dry-run"] : ["installer", "--dry-run"] }
    var note: String {
        kind == .purge
            ? "Projects modified in the last 7 days stay unchecked so your active work keeps its dependencies. Checked items move to the Trash."
            : "Disk images, packages and installer archives found in Downloads, Desktop, Homebrew caches and other download folders. Checked items move to the Trash."
    }

    var available: [Entry] { entries.filter { !removed.contains($0.id) && !gone.contains($0.id) } }
    var reclaimable: Double { available.reduce(0) { $0 + $1.bytes } }
    var selectedEntries: [Entry] { available.filter { selected.contains($0.id) } }
    var selectedTotal: Double { selectedEntries.reduce(0) { $0 + $1.bytes } }

    func toggle(_ entry: Entry) {
        guard phase != .working, !removed.contains(entry.id) else { return }
        if selected.contains(entry.id) { selected.remove(entry.id) } else { selected.insert(entry.id) }
    }

    func selectAll() { selected = Set(available.map(\.id)) }
    func selectNone() { selected = [] }

    // MARK: Scan

    func scanIfNeeded() {
        if !scanned && phase == .idle { scan() }
    }

    func scan() {
        guard phase != .scanning && phase != .working else { return }
        cancelled = false
        withAnimation(Motion.easeOut(0.3)) {
            phase = .scanning
            entries = []
            selected = []
            scanned = false
        }
        app.terminal.log("mo " + command.joined(separator: " "), .cmd)
        Task { await runScan() }
    }

    private func runScan() async {
        var found: [Entry] = []
        var raw: [InstallerParser.Item] = []
        do {
            let proc = try await MoleRunner.shared.start(command)
            process = proc
            for await line in proc.lines {
                if kind == .purge {
                    app.terminal.stream(line)
                    if let item = PurgeParser.item(line.text) {
                        let entry = makePurgeEntry(item)
                        found.append(entry)
                        // Stream rows in while Mole keeps scanning.
                        withAnimation(Motion.easeOut(0.35)) {
                            if entries.count == found.count - 1 && !scanned { entries.append(entry) } else { entries = found }
                            if !entry.recent { selected.insert(entry.id) }
                        }
                    }
                } else if let item = InstallerParser.item(line.text) {
                    app.terminal.log(line.text.trimmingCharacters(in: .whitespaces))
                    raw.append(item)
                } else if !line.text.contains("Space Select") {
                    app.terminal.stream(line)
                }
            }
            _ = await proc.waitForExit()
            process = nil
        } catch {
            app.terminal.log(error.localizedDescription, .warn)
        }
        if cancelled { return }
        if kind == .installers {
            found = await Task.detached { raw.compactMap(Self.makeInstallerEntry) }.value
        }
        found.sort { $0.bytes > $1.bytes }
        let total = found.reduce(0) { $0 + $1.bytes }
        app.terminal.log(found.isEmpty ? "Nothing found." : "Found \(found.count) items · \(Fmt.size(total))", found.isEmpty ? .dim : .ok)
        withAnimation(Motion.easeOut(0.45)) {
            entries = found
            removed = []
            gone = []
            selected = Set(found.filter { !$0.recent }.map(\.id))
            scanned = true
            phase = .ready
        }
    }

    private func makePurgeEntry(_ item: PurgeParser.Item) -> Entry {
        let path = Fmt.expandTilde(item.path)
        let url = URL(fileURLWithPath: path)
        let project = url.deletingLastPathComponent().path
        let dates = [FileInfo.modified(path), FileInfo.modified(project)].compactMap { $0 }
        let modified = dates.max()
        let recent = modified.map { Date().timeIntervalSince($0) < 7 * 86_400 } ?? true
        return Entry(id: path, path: path, tag: url.lastPathComponent, name: Fmt.tildePath(path),
                     sub: "Last modified \(Fmt.relative(modified).lowercased())", bytes: item.bytes, recent: recent)
    }

    nonisolated private static func makeInstallerEntry(_ item: InstallerParser.Item) -> Entry? {
        guard let path = InstallerParser.resolve(item) else { return nil }
        let url = URL(fileURLWithPath: path)
        var ext = url.pathExtension.lowercased()
        if ext.isEmpty { ext = "file" }
        let added = FileInfo.added(path)
        let folder = Fmt.tildePath(url.deletingLastPathComponent().path)
        return Entry(id: path, path: path, tag: ext, name: url.lastPathComponent,
                     sub: "\(folder) · downloaded \(Fmt.relative(added).lowercased())", bytes: item.bytes, recent: false)
    }

    func cancel() {
        if let process {
            cancelled = true
            process.cancel()
            self.process = nil
            app.terminal.log("Scan cancelled", .warn)
            withAnimation { phase = scanned ? .ready : .idle }
        } else if phase == .working {
            cancelled = true
        }
    }

    // MARK: Remove

    func run() {
        guard phase != .working, phase != .scanning else { return }
        let items = selectedEntries
        guard !items.isEmpty else { return }
        cancelled = false
        doneCount = 0
        totalCount = items.count
        withAnimation(Motion.easeOut(0.3)) {
            phase = .working
            gone = []
        }
        Task { await remove(items) }
    }

    private func remove(_ items: [Entry]) async {
        app.terminal.log("mv " + (items.count == 1 ? "\"\(Fmt.tildePath(items[0].path))\"" : "\(items.count) items") + " ~/.Trash/", .cmd)
        try? await Task.sleep(for: .milliseconds(200))
        var freedNow: Double = 0
        var count = 0
        for item in items {
            if cancelled { break }
            let started = Date()
            let ok = await Trash.move(item.path)
            if ok {
                app.terminal.log("→ Trash  \(Fmt.tildePath(item.path))  \(Fmt.size(item.bytes))")
                freedNow += item.bytes
                count += 1
                withAnimation(Motion.easeIn(0.45)) { _ = gone.insert(item.id) }
            } else {
                app.terminal.log("Could not move \(Fmt.tildePath(item.path)) to the Trash", .warn)
            }
            doneCount += 1
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.17 { try? await Task.sleep(for: .milliseconds(Int((0.17 - elapsed) * 1000))) }
        }
        try? await Task.sleep(for: .milliseconds(300))
        app.terminal.log("Moved \(Fmt.size(freedNow)) from \(count) items to the Trash", .ok)
        app.toast(kind == .purge ? "Artifacts purged" : "Installers removed", "\(Fmt.size(freedNow)) to Trash · \(count) items")
        app.disk.refreshAfterAction()
        withAnimation(Motion.easeOut(0.45)) {
            removed.formUnion(gone)
            selected.subtract(gone)
            gone = []
            freed = freedNow
            freedCount = count
            phase = .done
        }
    }
}
