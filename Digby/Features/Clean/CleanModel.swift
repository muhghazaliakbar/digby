import Foundation
import Observation
import SwiftUI

@Observable
final class CleanModel {
    enum Phase { case idle, scanning, results, cleaning, done, empty }

    struct Item: Identifiable, Equatable {
        let id: String
        let path: String
        let bytes: Double
        /// Rows without a real path (e.g. "npm cache") are cleaned by Mole as a whole and cannot be excluded.
        var excludable: Bool { path.hasPrefix("/") }
    }

    struct Category: Identifiable, Equatable {
        let id: String
        let name: String
        let detail: String
        let colorIndex: Int
        var items: [Item]
        var total: Double { items.reduce(0) { $0 + $1.bytes } }
        var color: Color { DS.palette[colorIndex % DS.palette.count] }
    }

    struct Chip: Identifiable, Equatable {
        let id: String
        let name: String
        let bytes: Double
        let colorIndex: Int
    }

    @ObservationIgnored unowned let app: AppModel
    var phase: Phase = .idle
    var dryRun = false
    var progress: Double = 0
    var currentPath = ""
    var chips: [Chip] = []
    var foundBytes: Double = 0
    var categories: [Category] = []
    var selected: Set<String> = []
    var openCategory: String?
    var freed: Double = 0
    var freedItems = 0
    var lastDry = false
    var burstID = 0

    @ObservationIgnored private var process: MoleProcess?
    @ObservationIgnored private var whitelistDefaults: [String] = []
    @ObservationIgnored private var scanSections = 15
    @ObservationIgnored private var cancelled = false

    init(app: AppModel) { self.app = app }

    // MARK: Derived

    var resultTotal: Double { categories.reduce(0) { $0 + $1.total } }
    var selectedTotal: Double { categories.reduce(0) { $0 + selectedBytes(in: $1) } }
    var itemCount: Int { categories.reduce(0) { $0 + $1.items.count } }
    var selectedCount: Int { categories.reduce(0) { $0 + $1.items.filter { selected.contains($0.id) }.count } }

    func selectedBytes(in category: Category) -> Double {
        category.items.reduce(0) { $0 + (selected.contains($1.id) ? $1.bytes : 0) }
    }

    func state(of category: Category) -> CheckState {
        let n = category.items.filter { selected.contains($0.id) }.count
        return n == 0 ? .none : n == category.items.count ? .all : .some
    }

    // MARK: Selection

    func toggle(_ category: Category) {
        let on = state(of: category) != .all
        for item in category.items where item.excludable || on {
            if on { selected.insert(item.id) } else { selected.remove(item.id) }
        }
    }

    func toggle(_ item: Item) {
        guard item.excludable else { return }
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }

    func selectAll() { selected = Set(categories.flatMap(\.items).map(\.id)) }
    func selectNone() { selected = Set(categories.flatMap(\.items).filter { !$0.excludable }.map(\.id)) }

    func toggleOpen(_ category: Category) {
        withAnimation(Motion.easeOut(0.4)) { openCategory = openCategory == category.id ? nil : category.id }
    }

    // MARK: Scan

    func startScan() {
        guard phase != .scanning && phase != .cleaning else { return }
        cancelled = false
        withAnimation(Motion.easeOut(0.4)) {
            phase = .scanning
            progress = 0
            chips = []
            foundBytes = 0
            currentPath = "Preparing scan…"
            openCategory = nil
        }
        app.terminal.log("mo clean --dry-run", .cmd)
        Task { await runScan() }
    }

    private func runScan() async {
        let started = Date()
        var parser = CleanParser()
        var sections: [String] = []
        var bySection: [String: [(String, Double)]] = [:]
        var defaults: [String] = []
        var finishedSections = 0

        func closeSection(_ name: String?) {
            guard let name else { return }
            finishedSections += 1
            let total = (bySection[name] ?? []).reduce(0) { $0 + $1.1 }
            if total > 0 {
                withAnimation(Motion.overshoot(0.45, 1.6)) {
                    chips.append(Chip(id: name, name: name, bytes: total, colorIndex: chips.count))
                }
            }
        }

        do {
            let proc = try await MoleRunner.shared.start(["clean", "--dry-run"])
            process = proc
            let creep = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(120))
                    guard let self, self.phase == .scanning else { return }
                    let target = min(0.97, (Double(finishedSections) + 0.85) / Double(self.scanSections))
                    if self.progress < target { self.progress += (target - self.progress) * 0.06 }
                }
            }
            for await line in proc.lines {
                app.terminal.stream(line)
                let previous = parser.section
                guard let event = parser.feed(line.text) else { continue }
                switch event {
                case .section(let name):
                    closeSection(previous)
                    sections.append(name)
                    currentPath = name
                    withAnimation(Motion.easeOut(0.3)) {
                        progress = max(progress, min(0.97, Double(finishedSections) / Double(scanSections)))
                    }
                case .item(let section, let name, let bytes):
                    bySection[section, default: []].append((name, bytes))
                    currentPath = name
                    foundBytes += bytes
                case .whitelist(let path):
                    defaults.append(path)
                case .summary:
                    break
                }
            }
            closeSection(parser.section)
            creep.cancel()
            let status = await proc.waitForExit()
            process = nil
            if cancelled { return }
            if status != 0 && sections.isEmpty {
                app.terminal.log("mo clean exited with status \(status)", .warn)
            }
        } catch {
            app.terminal.log(error.localizedDescription, .warn)
            withAnimation { phase = .idle }
            return
        }

        whitelistDefaults = defaults
        scanSections = max(sections.count, 1)
        let built = buildCategories(sections: sections, bySection: bySection, since: started)
        withAnimation(Motion.easeOut(0.3)) { progress = 1 }
        let total = built.reduce(0) { $0 + $1.total }
        app.terminal.log(total > 0 ? "Found \(Fmt.size(total)) in \(built.count) categories." : "Nothing to clean.")
        try? await Task.sleep(for: .milliseconds(total > 0 ? 450 : 0))
        categories = built
        selected = Set(built.flatMap(\.items).map(\.id))
        withAnimation(Motion.easeOut(0.45)) { phase = total > 0 ? .results : .empty }
        #if DEBUG
        // Debug-only hook: `-autoPreview YES` runs a dry-run preview with one location unchecked.
        if UserDefaults.standard.bool(forKey: "autoPreview"), let item = categories.flatMap(\.items).first(where: \.excludable) {
            try? await Task.sleep(for: .seconds(2))
            selected.remove(item.id)
            dryRun = true
            startClean()
        }
        #endif
    }

    /// Prefers the per-path preview Mole writes to clean-list.txt; falls back to the summary rows.
    private func buildCategories(sections: [String], bySection: [String: [(String, Double)]], since: Date) -> [Category] {
        var listed: [String: [CleanListParser.Entry]] = [:]
        let url = CleanListParser.defaultURL
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modified = attrs[.modificationDate] as? Date, modified >= since.addingTimeInterval(-5),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            for section in CleanListParser.parse(text) { listed[section.name] = section.entries }
        }

        var result: [Category] = []
        for name in sections {
            var items: [Item] = []
            if let entries = listed[name], !entries.isEmpty {
                items = entries.filter { $0.bytes > 0 }.map { Item(id: name + "|" + $0.path, path: $0.path, bytes: $0.bytes) }
            }
            if items.isEmpty {
                items = (bySection[name] ?? []).enumerated().map { i, row in
                    Item(id: name + "|" + row.0 + "#\(i)", path: row.0, bytes: row.1)
                }
            }
            items = items.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
            guard !items.isEmpty else { continue }
            result.append(Category(id: name, name: name, detail: Self.detail(for: name, count: items.count), colorIndex: result.count, items: items))
        }
        return result
    }

    static func detail(for section: String, count: Int) -> String {
        let known: [String: String] = [
            "User essentials": "User app caches, logs and the Trash",
            "App caches": "Rebuildable cache files in ~/Library/Caches",
            "Browsers": "Service worker storage, code caches and crash reports",
            "Cloud & Office": "Cloud storage and Office caches",
            "Developer tools": "Xcode DerivedData, simulators, npm, pip, Homebrew, Gradle",
            "Apps & utilities": "Caches and logs from installed apps",
            "Virtualization": "Virtual machine and container caches",
            "Application Support": "Logs and caches inside Application Support",
            "App leftovers": "Support files from apps that are no longer installed",
            "Apple Silicon updates": "Leftover Rosetta and software update files",
            "Device backups & firmware": "Old device backups and firmware files",
            "Time Machine": "Incomplete Time Machine backups",
            "System": "System caches and temporary files",
        ]
        return known[section] ?? "\(count) location\(count == 1 ? "" : "s")"
    }

    func cancel() {
        guard let process else { return }
        cancelled = true
        process.cancel()
        app.terminal.log(phase == .scanning ? "Scan cancelled" : "Clean cancelled", .warn)
        withAnimation(Motion.easeOut(0.4)) {
            phase = phase == .scanning ? .idle : .results
            progress = 0
        }
    }

    // MARK: Clean

    func startClean() {
        guard phase == .results, selectedTotal > 0 else { return }
        let dry = dryRun
        let exclusions = categories.flatMap(\.items).filter { $0.excludable && !selected.contains($0.id) }.map(\.path)
        let target = selectedTotal
        cancelled = false
        withAnimation(Motion.easeOut(0.45)) {
            phase = .cleaning
            progress = 0
            freed = 0
            currentPath = categories.first?.items.first?.path ?? ""
        }
        Task { await runClean(dry: dry, exclusions: exclusions, target: target) }
    }

    private func runClean(dry: Bool, exclusions: [String], target: Double) async {
        let freeBefore = app.disk.free
        var args = ["clean"]
        if dry { args.append("--dry-run") }
        if !exclusions.isEmpty {
            do {
                try WhitelistGuard.apply(defaults: whitelistDefaults, exclusions: exclusions)
                app.terminal.log("Excluding \(exclusions.count) unchecked location\(exclusions.count == 1 ? "" : "s") via ~/.config/mole/whitelist (restored after the run)", .dim)
            } catch {
                app.terminal.log("Could not apply exclusions: \(error.localizedDescription). Nothing was cleaned.", .warn)
                withAnimation { phase = .results }
                return
            }
        }
        defer { if !exclusions.isEmpty { WhitelistGuard.restore() } }

        app.terminal.log("mo " + args.joined(separator: " "), .cmd)
        var parser = CleanParser()
        var sectionsDone = 0
        var parsedBytes: Double = 0
        var summaryBytes: Double?
        var summaryItems: Int?
        do {
            let proc = try await MoleRunner.shared.start(args)
            process = proc
            for await line in proc.lines {
                app.terminal.stream(line)
                guard let event = parser.feed(line.text) else { continue }
                switch event {
                case .section(let name):
                    sectionsDone += 1
                    currentPath = name
                    withAnimation(Motion.easeOut(0.4)) { progress = min(0.97, Double(sectionsDone) / Double(scanSections + 1)) }
                case .item(_, let name, let bytes):
                    parsedBytes += bytes
                    currentPath = name
                    withAnimation(Motion.count(0.6)) { freed = min(parsedBytes, max(target, parsedBytes)) }
                case .summary(let bytes, let items):
                    summaryBytes = bytes
                    summaryItems = items
                case .whitelist:
                    break
                }
            }
            _ = await proc.waitForExit()
            process = nil
        } catch {
            app.terminal.log(error.localizedDescription, .warn)
            withAnimation { phase = .results }
            return
        }
        if cancelled { return }

        app.disk.refreshAfterAction()
        let diskDelta = max(0, app.disk.free - freeBefore)
        let total = summaryBytes ?? (parsedBytes > 0 ? parsedBytes : (dry ? target : diskDelta))
        freedItems = summaryItems ?? selectedCount
        lastDry = dry
        app.terminal.log(dry ? "Dry run complete. \(Fmt.size(total)) could be freed." : "Done. Freed \(Fmt.size(total)) across \(Fmt.grouped(freedItems)) items.", .ok)
        app.toast(dry ? "Dry run finished" : "Clean complete", "\(Fmt.size(total)) \(dry ? "could be freed" : "freed")", color: dry ? DS.accent : DS.success)
        withAnimation(Motion.easeOut(0.3)) { progress = 1 }
        freed = total
        if !dry { burstID += 1 }
        withAnimation(Motion.easeOut(0.5)) { phase = .done }
    }

    func backToResults() {
        withAnimation(Motion.easeOut(0.45)) { phase = .results }
    }
}
