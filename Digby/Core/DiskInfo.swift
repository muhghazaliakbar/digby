import Foundation
import Observation

/// Free/used space of the startup volume, refreshed after every destructive action.
@Observable
final class DiskInfo {
    private(set) var total: Double = 0
    private(set) var free: Double = 0
    /// True while the free-space label is counting to its new value (tints it green).
    private(set) var tweening = false
    private(set) var volumeName = "Macintosh HD"
    @ObservationIgnored private var tweenTask: Task<Void, Never>?

    var used: Double { max(0, total - free) }
    var usedFraction: Double { total > 0 ? used / total : 0 }

    @ObservationIgnored private var monitor: Task<Void, Never>?

    init() {
        refresh(animated: false)
        // Keeps the menu bar value current while the app is idle.
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.refresh()
            }
        }
    }

    func refresh(animated: Bool = true) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return }
        let newTotal = Double(values.volumeTotalCapacity ?? 0)
        let newFree = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
        volumeName = values.volumeLocalizedName ?? volumeName
        let changed = abs(newFree - free) > 50_000_000
        total = newTotal
        free = newFree
        if animated && changed {
            tweening = true
            tweenTask?.cancel()
            tweenTask = Task {
                try? await Task.sleep(for: .milliseconds(1100))
                if !Task.isCancelled { tweening = false }
            }
        }
    }

    /// Re-reads after a delay too, because APFS reports purged space lazily.
    func refreshAfterAction() {
        refresh()
        Task {
            try? await Task.sleep(for: .seconds(2))
            refresh()
        }
    }
}
