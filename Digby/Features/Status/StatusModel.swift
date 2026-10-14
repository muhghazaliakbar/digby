import Darwin
import Foundation
import Observation
import SwiftUI

@Observable
final class StatusModel {
    struct Proc: Identifiable, Equatable {
        let id: String
        var cpu: Double
        var memory: Double
    }

    struct Battery: Equatable {
        var percent: Double
        var status: String
        var capacity: Double?
        var cycles: Int?
        var temperature: Double?
        var watts: Double?
        var timeLeft: String?
    }

    @ObservationIgnored unowned let app: AppModel

    var loaded = false
    var healthScore = 0
    var healthLabel = "—"
    var uptime = ""
    var osVersion = ""
    var cpuModel = ""
    var pCores: [Double] = []
    var eCores: [Double] = []
    var cpuUsage: Double = 0
    var cpuTemp: Double = 0
    var cpuHistory: [Double] = Array(repeating: 0, count: 48)
    var memTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    var memApp: Double = 0
    var memWired: Double = 0
    var memCompressed: Double = 0
    var swapUsed: Double = 0
    var pressure = "normal"
    var diskRead: Double = 0
    var diskWrite: Double = 0
    var netDown: [Double] = Array(repeating: 0, count: 48)
    var netUp: [Double] = Array(repeating: 0, count: 48)
    var procs: [Proc] = []
    var battery: Battery?
    var interfaceName = "Network"

    @ObservationIgnored private var process: MoleProcess?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var fullTask: Task<Void, Never>?
    @ObservationIgnored private var eCoreCount: Int?
    @ObservationIgnored private var watchHasCores = false

    init(app: AppModel) { self.app = app }

    var memUsed: Double { memApp + memWired + memCompressed }

    func start() {
        guard task == nil else { return }
        task = Task { await stream() }
        // Watch snapshots are lightweight; a full snapshot fills processes, battery and hardware.
        fullTask = Task {
            while !Task.isCancelled {
                if let (data, _) = try? await MoleRunner.shared.captureData(["status", "--json"]),
                   let start = data.firstIndex(of: UInt8(ascii: "{")),
                   let snap = StatusSnapshot.decode(data[start...]) {
                    apply(snap, full: true)
                }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        fullTask?.cancel()
        fullTask = nil
        process?.cancel()
        process = nil
    }

    func restart() {
        stop()
        start()
    }

    /// `mo status --watch` streams newline-delimited JSON; falls back to polling `--json`.
    private func stream() async {
        app.terminal.log("mo status --watch --interval 1s", .cmd)
        do {
            let proc = try await MoleRunner.shared.start(["status", "--watch", "--interval", "1s"])
            process = proc
            var buffer = ""
            var depth = 0
            var received = 0
            for await line in proc.lines where !line.isError {
                if Task.isCancelled { break }
                let text = line.text
                if depth == 0 && !text.trimmingCharacters(in: .whitespaces).hasPrefix("{") { continue }
                buffer += text + "\n"
                depth += text.filter { $0 == "{" }.count - text.filter { $0 == "}" }.count
                if depth <= 0 {
                    if let snap = StatusSnapshot.decode(Data(buffer.utf8)) {
                        apply(snap)
                        received += 1
                    }
                    buffer = ""
                    depth = 0
                }
            }
            process = nil
            if received > 0 || Task.isCancelled { return }
        } catch {
            app.terminal.log(error.localizedDescription, .warn)
        }
        // Older Mole versions without --watch: the full-snapshot poll keeps the cards alive.
    }

    private func apply(_ s: StatusSnapshot, full: Bool = false) {
        let anim = Motion.overshoot(0.9, 1.25)
        withAnimation(anim) {
            if let score = s.health_score { healthScore = score }
            healthLabel = s.health_score_msg ?? (healthScore >= 85 ? "Excellent" : healthScore >= 70 ? "Good" : "Needs attention")
            if let e = s.cpu?.e_core_count, s.cpu?.p_core_count != nil { eCoreCount = e }
            uptime = s.uptime ?? uptime
            osVersion = s.hardware?.os_version ?? osVersion
            cpuModel = s.hardware?.cpu_model ?? cpuModel

            if let cpu = s.cpu, let cores = cpu.per_core, !cores.isEmpty, !full || !watchHasCores {
                if !full { watchHasCores = true }
                let e = min(eCoreCount ?? cpu.e_core_count ?? 0, cores.count)
                // Apple Silicon numbers efficiency cores first; show performance cores first like the design.
                eCores = Array(cores.prefix(e))
                pCores = Array(cores.dropFirst(e))
                cpuUsage = cpu.usage ?? cpuUsage
                cpuHistory = Array((cpuHistory + [cpuUsage]).suffix(48))
            }
            if let t = s.thermal?.cpu_temp { cpuTemp = t }

            let mem = NativeStats.memory()
            memTotal = mem.total
            memApp = mem.app
            memWired = mem.wired
            memCompressed = mem.compressed
            swapUsed = s.memory?.swap_used ?? mem.swap
            let p = s.memory?.pressure ?? ""
            pressure = p.isEmpty ? (memUsed / max(memTotal, 1) > 0.9 ? "high" : "normal") : p

            if !full {
                diskRead = s.disk_io?.read_rate ?? diskRead
                diskWrite = s.disk_io?.write_rate ?? diskWrite
                let rates = s.networkRates
                netDown = Array((netDown + [rates.down]).suffix(48))
                netUp = Array((netUp + [rates.up]).suffix(48))
            }
            if let primary = s.network?.first(where: { !($0.ip ?? "").isEmpty && !($0.name ?? "").hasPrefix("utun") })?.name {
                interfaceName = primary == "en0" ? "Wi-Fi" : primary
            }

            if let procs = s.top_processes, !procs.isEmpty { mergeProcesses(procs) }

            if let b = s.batteries?.first {
                battery = Battery(percent: b.percent ?? 0, status: b.status ?? "", capacity: b.capacity, cycles: b.cycle_count,
                                  temperature: s.thermal?.battery_temp, watts: s.thermal?.adapter_power, timeLeft: b.time_left)
            } else if full {
                battery = nil
            }
        }
        if !loaded {
            loaded = true
        }
    }

    /// Keeps row identity stable so rows physically reorder by CPU.
    private func mergeProcesses(_ fresh: [StatusSnapshot.Proc]) {
        var next = procs
        for p in fresh {
            guard let name = p.name else { continue }
            let id = name
            if let i = next.firstIndex(where: { $0.id == id }) {
                next[i].cpu = p.cpu ?? 0
                next[i].memory = p.memory_bytes ?? 0
            } else {
                next.append(Proc(id: id, cpu: p.cpu ?? 0, memory: p.memory_bytes ?? 0))
            }
        }
        let freshNames = Set(fresh.compactMap(\.name))
        for i in next.indices where !freshNames.contains(next[i].id) {
            next[i].cpu *= 0.5
        }
        next.sort { $0.cpu > $1.cpu }
        procs = Array(next.prefix(7))
    }

    func rank(of proc: Proc) -> Int {
        procs.sorted { $0.cpu > $1.cpu }.firstIndex(of: proc) ?? 0
    }
}

/// Memory breakdown that `mo status --json` does not provide (App / Wired / Compressed).
nonisolated enum NativeStats {
    struct Memory { var total: Double; var app: Double; var wired: Double; var compressed: Double; var swap: Double }

    static func memory() -> Memory {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let page = Double(getpagesize())
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else { return Memory(total: total, app: 0, wired: 0, compressed: 0, swap: 0) }
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        return Memory(total: total,
                      app: max(0, app) * page,
                      wired: Double(stats.wire_count) * page,
                      compressed: Double(stats.compressor_page_count) * page,
                      swap: Double(swap.xsu_used))
    }
}
