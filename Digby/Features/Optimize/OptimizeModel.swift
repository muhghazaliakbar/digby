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

    /// The tasks in Mole's optimize catalog (lib/optimize/catalog.sh). Names match the section headers
    /// Mole prints, which is how progress is tracked; descriptions are Digby's own. Mole runs every task
    /// in one pass and offers no per-task flag, so toggles are read-only; `mo optimize --whitelist` excludes tasks.
    static let catalog: [OptTask] = [
        ("DNS & Spotlight Check", "Clears cached hostname lookups and checks that Spotlight is still indexing", "opt_system_maintenance", true),
        ("Finder Cache Refresh", "Rebuilds the Quick Look previews and icon cache Finder draws from", "opt_cache_refresh", false),
        ("App State Cleanup", "Deletes window-restore data that apps saved more than 30 days ago", "opt_saved_state_cleanup", false),
        ("Broken Config Repair", "Finds preference files that no longer open and repairs them", "opt_fix_broken_configs", false),
        ("Network Cache Refresh", "Clears cached hostname lookups after you switch networks", "opt_network_optimization", true),
        ("Database Optimization", "Compacts the Mail, Safari and Messages databases while those apps are closed", "opt_sqlite_vacuum", false),
        ("Prevent Finder .DS_Store", "Keeps Finder from leaving .DS_Store files on network shares and USB drives", "opt_prevent_network_dsstore", false),
        ("Legacy Overrides", "Turns App Nap and disk-image checks back on where old tweak tools disabled them", "opt_legacy_overrides_audit", false),
        ("Network Stack Refresh", "Resets the routing table and ARP cache when connections misbehave", "opt_network_stack_optimize", true),
        ("Permission Repair", "Restores the expected permissions on folders in your home directory", "opt_disk_permissions_repair", false),
        ("Spotlight Optimization", "Rebuilds the Spotlight index, but only when searches look slow", "opt_spotlight_index_optimize", true),
        ("Spotlight Orphan Rules", "Drops Spotlight search rules left behind by apps you deleted", "opt_prune_spotlight_orphan_rules", false),
        ("Periodic Maintenance", "Runs the daily, weekly and monthly macOS scripts when they are overdue", "opt_periodic_maintenance", true),
        ("Shared File Lists", "Fixes damaged Finder sidebar favorites and recent-item lists", "opt_shared_file_list_repair", false),
        ("Disk Health", "Checks the startup disk's file system for errors", "opt_disk_verify", true),
        ("Login Items", "Looks for login items that point to apps that are gone", "opt_login_items_audit", false),
        ("Quarantine Database Cleanup", "Clears Gatekeeper's record of where downloaded files came from", "opt_quarantine_cleanup", false),
        ("Launch Agents Cleanup", "Lists launch agents whose program no longer exists", "opt_launch_agents_cleanup", false),
        ("Notifications", "Prunes old delivered notifications so their database stays small", "opt_notification_cleanup", false),
        ("Usage Data", "Removes old app-usage history that macOS keeps for suggestions", "opt_coreduet_cleanup", false),
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
