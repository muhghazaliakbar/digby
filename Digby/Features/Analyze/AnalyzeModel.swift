import Foundation
import Observation
import SwiftUI

@Observable
final class AnalyzeModel {
    enum Direction { case none, into, out }

    struct Node: Identifiable, Equatable, Hashable {
        var id: String { path }
        let name: String
        let path: String
        let size: Double
        let isDir: Bool
    }

    @ObservationIgnored unowned let app: AppModel
    let root = NSHomeDirectory()
    var stack: [String] = []
    var cache: [String: [Node]] = [:]
    var loadingPath: String?
    var failed: Set<String> = []
    var removed: Set<String> = []
    var selected: String?
    var direction: Direction = .none
    var changes = 0
    var origin: UnitPoint = .center
    var morph = false
    @ObservationIgnored private var process: MoleProcess?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    var currentPath: String { stack.last ?? root }
    var displayPath: String { Fmt.tildePath(currentPath) }
    var crumbs: [(name: String, path: String)] {
        [("~", root)] + stack.map { (URL(fileURLWithPath: $0).lastPathComponent, $0) }
    }

    var children: [Node] {
        (cache[currentPath] ?? []).filter { !removed.contains($0.path) && $0.size > 0 }.sorted { $0.size > $1.size }
    }

    var total: Double { children.reduce(0) { $0 + $1.size } }
    var isLoading: Bool { loadingPath == currentPath && cache[currentPath] == nil }

    func loadIfNeeded() { load(currentPath) }

    func rescan() {
        cache[currentPath] = nil
        load(currentPath)
    }

    func cancel() {
        loadTask?.cancel()
        process?.cancel()
        process = nil
        loadingPath = nil
    }

    private func load(_ path: String) {
        guard cache[path] == nil, loadingPath != path else { return }
        loadTask?.cancel()
        loadingPath = path
        failed.remove(path)
        app.terminal.log("mo analyze --json \"\(Fmt.tildePath(path))\"", .cmd)
        loadTask = Task {
            let started = Date()
            let result = try? await MoleRunner.shared.captureData(["analyze", "--json", path])
            if Task.isCancelled { return }
            guard let (data, _) = result, let report = AnalyzeReport.decode(data) else {
                app.terminal.log("Could not analyze \(Fmt.tildePath(path))", .warn)
                failed.insert(path)
                if loadingPath == path { loadingPath = nil }
                return
            }
            let nodes = (report.entries ?? []).map { Node(name: $0.name, path: $0.path, size: $0.size, isDir: $0.is_dir ?? false) }
            app.terminal.log("\(nodes.count) items · \(Fmt.size(report.total_size ?? nodes.reduce(0) { $0 + $1.size })) · \(String(format: "%.1f", Date().timeIntervalSince(started)))s", .ok)
            if report.scan_status == "partial" { app.terminal.log("Partial scan: some folders could not be read", .warn) }
            withAnimation(Motion.easeOut(0.4)) {
                cache[path] = nodes
                if loadingPath == path { loadingPath = nil }
            }
        }
    }

    // MARK: Navigation

    func drill(_ node: Node, origin: UnitPoint = .center) {
        guard node.isDir else { return }
        stack.append(node.path)
        selected = nil
        direction = .into
        self.origin = origin
        morph = false
        changes += 1
        load(node.path)
    }

    func up() {
        guard !stack.isEmpty else { return }
        go(to: stack.count - 1)
    }

    /// Jumps to crumb `index` (0 = home).
    func go(to index: Int) {
        guard index < stack.count + 1, index != stack.count else { return }
        stack = Array(stack.prefix(index))
        selected = nil
        direction = .out
        origin = .center
        morph = false
        changes += 1
        load(currentPath)
    }

    func trash(_ node: Node) {
        Task {
            app.terminal.log("mv \"\(Fmt.tildePath(node.path))\" ~/.Trash/", .cmd)
            guard await Trash.move(node.path) else {
                app.terminal.log("Could not move \(node.name) to the Trash", .warn)
                return
            }
            app.toast("Moved to Trash", "\(node.name) · \(Fmt.size(node.size))", color: DS.orange)
            app.disk.refreshAfterAction()
            morph = true
            withAnimation(Motion.overshoot(0.5, 1.1)) {
                removed.insert(node.path)
                if selected == node.path { selected = nil }
            }
            // Parent folder totals are now stale.
            for key in cache.keys where node.path.hasPrefix(key + "/") && key != currentPath { cache[key] = nil }
        }
    }
}

/// Squarified treemap layout (Bruls et al.), as in the design.
nonisolated enum Treemap {
    struct Tile<T> { let item: T; let rect: CGRect }

    static func layout<T>(_ items: [(T, Double)], in rect: CGRect) -> [Tile<T>] {
        var out: [Tile<T>] = []
        var rest = items.filter { $0.1 > 0 }
        var total = rest.reduce(0) { $0 + $1.1 }
        var x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
        while !rest.isEmpty && w > 0 && h > 0 && total > 0 {
            let k = w * h / total
            let side = min(w, h)
            var row: [(T, Double)] = []
            var rowSum = 0.0
            var best = Double.infinity
            for item in rest {
                let s = rowSum + item.1 * k
                let vals = row.map { $0.1 * k } + [item.1 * k]
                let mx = vals.max()!, mn = vals.min()!
                let worst = max(side * side * mx / (s * s), (s * s) / (side * side * mn))
                if !row.isEmpty && worst > best { break }
                best = worst
                row.append(item)
                rowSum = s
            }
            let thickness = rowSum / side
            var offset = 0.0
            for item in row {
                let length = item.1 * k / thickness
                let r = w >= h
                    ? CGRect(x: x, y: y + offset, width: thickness, height: length)
                    : CGRect(x: x + offset, y: y, width: length, height: thickness)
                out.append(Tile(item: item.0, rect: r))
                offset += length
            }
            if w >= h { x += thickness; w -= thickness } else { y += thickness; h -= thickness }
            total -= row.reduce(0) { $0 + $1.1 }
            rest.removeFirst(row.count)
        }
        return out
    }
}
