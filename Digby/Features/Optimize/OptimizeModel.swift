import Foundation
import Observation
import SwiftUI

@Observable
final class OptimizeModel {
    enum Phase { case idle, running, done }
    enum TaskStatus: Equatable { case idle, queued, running, done }

    struct OptTask: Identifiable, Equatable {
        let id: String
        let name: String
        let detail: String
        let handler: String
        let admin: Bool
        var status: TaskStatus = .idle
        var seconds: Double = 0
        var result: String = ""
    }

    @ObservationIgnored unowned let app: AppModel
    var phase: Phase = .idle
    var tasks: [OptTask] = OptimizeModel.catalog
    @ObservationIgnored private var process: MoleProcess?
    @ObservationIgnored private var cancelled = false

    init(app: AppModel) { self.app = app }

    /// Mirrors Mole's task catalog (lib/optimize/catalog.sh). Mole runs every task in one pass and
    /// offers no per-task flag, so toggles are read-only; `mo optimize --whitelist` excludes tasks.
    static let catalog: [OptTask] = [
        ("DNS & Spotlight Check", "Refresh DNS cache & verify Spotlight status", "opt_system_maintenance", true),
        ("Finder Cache Refresh", "Refresh QuickLook thumbnails & icon services cache", "opt_cache_refresh", false),
        ("App State Cleanup", "Remove old saved application states (30+ days)", "opt_saved_state_cleanup", false),
        ("Broken Config Repair", "Fix corrupted preferences files", "opt_fix_broken_configs", false),
        ("Network Cache Refresh", "Refresh DNS cache", "opt_network_optimization", true),
        ("Database Optimization", "Compress SQLite databases for Mail, Safari & Messages (skips if apps are running)", "opt_sqlite_vacuum", false),
        ("Prevent Finder .DS_Store", "Stop Finder writing .DS_Store on SMB/AFP/NFS and USB volumes", "opt_prevent_network_dsstore", false),
        ("Legacy Overrides", "Remove hidden App Nap and disk-image verification overrides left by old tweak tools", "opt_legacy_overrides_audit", false),
        ("Network Stack Refresh", "Flush routing table and ARP cache to resolve network issues", "opt_network_stack_optimize", true),
        ("Permission Repair", "Fix user directory permission issues", "opt_disk_permissions_repair", false),
        ("Spotlight Optimization", "Rebuild index if search is slow (smart detection)", "opt_spotlight_index_optimize", true),
        ("Spotlight Orphan Rules", "Remove Spotlight search-rule entries for apps that are no longer installed", "opt_prune_spotlight_orphan_rules", false),
        ("Periodic Maintenance", "Run macOS daily/weekly/monthly maintenance scripts if stale", "opt_periodic_maintenance", true),
        ("Shared File Lists", "Repair corrupted Finder favorites and recent documents", "opt_shared_file_list_repair", false),
        ("Disk Health", "Verify filesystem integrity", "opt_disk_verify", true),
        ("Login Items", "Audit login items for broken entries", "opt_login_items_audit", false),
        ("Quarantine Database Cleanup", "Clear Gatekeeper download tracking history", "opt_quarantine_cleanup", false),
        ("Launch Agents Cleanup", "Report LaunchAgents whose binaries no longer exist", "opt_launch_agents_cleanup", false),
        ("Notifications", "Clean old delivered notifications to reduce database bloat", "opt_notification_cleanup", false),
        ("Usage Data", "Clean old usage tracking data", "opt_coreduet_cleanup", false),
    ].map { OptTask(id: $0.0, name: $0.0, detail: $0.1, handler: $0.2, admin: $0.3) }

    var doneCount: Int { tasks.filter { $0.status == .done }.count }
    var fraction: Double { tasks.isEmpty || phase == .idle ? 0 : Double(doneCount) / Double(tasks.count) }

    func loadIfNeeded() {}
    func reload() { if phase != .running { run() } }

    func run() {
        guard phase != .running else { return }
        cancelled = false
        withAnimation(Motion.easeOut(0.35)) {
            phase = .running
            for i in tasks.indices {
                tasks[i].status = .queued
                tasks[i].seconds = 0
                tasks[i].result = ""
            }
        }
        Task { await execute() }
    }

    private func execute() async {
        app.terminal.log("mo optimize", .cmd)
        var current: Int?
        var started = Date()

        func finish(_ index: Int?) {
            guard let index else { return }
            let elapsed = Date().timeIntervalSince(started)
            withAnimation(Motion.overshoot(0.45, 1.7)) {
                tasks[index].status = .done
                tasks[index].seconds = elapsed
            }
            app.terminal.log("✓ \(tasks[index].name)  \(String(format: "%.1f", elapsed))s", .ok)
        }

        do {
            let proc = try await MoleRunner.shared.start(["optimize"])
            process = proc
            for await line in proc.lines {
                app.terminal.stream(line)
                switch OptimizeParser.event(line.text) {
                case .section(let name):
                    finish(current)
                    current = tasks.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                        ?? tasks.firstIndex { name.localizedCaseInsensitiveContains($0.name) || $0.name.localizedCaseInsensitiveContains(name) }
                    started = Date()
                    if let current {
                        withAnimation(Motion.easeOut(0.35)) { tasks[current].status = .running }
                    }
                case .detail(let text):
                    if let current, tasks[current].result.isEmpty { tasks[current].result = text }
                case .finished:
                    finish(current)
                    current = nil
                case nil:
                    break
                }
            }
            finish(current)
            let status = await proc.waitForExit()
            process = nil
            if cancelled { return }
            if status != 0 { app.terminal.log("mo optimize exited with status \(status)", .warn) }
        } catch {
            app.terminal.log(error.localizedDescription, .warn)
        }
        withAnimation(Motion.easeOut(0.35)) {
            for i in tasks.indices where tasks[i].status != .done {
                tasks[i].status = .done
                if tasks[i].result.isEmpty { tasks[i].result = "Skipped" }
            }
            phase = .done
        }
        app.terminal.log("All \(tasks.count) tasks finished", .ok)
        app.toast("Optimization complete", "\(tasks.count) tasks finished", color: DS.accent)
    }

    func cancel() {
        guard let process else { return }
        cancelled = true
        process.cancel()
        app.terminal.log("Optimize cancelled", .warn)
        withAnimation(Motion.easeOut(0.35)) {
            for i in tasks.indices where tasks[i].status != .done { tasks[i].status = .idle }
            phase = .idle
        }
    }
}
