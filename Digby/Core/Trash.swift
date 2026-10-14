import AppKit

/// Moves files to the Trash via Finder (handles admin-owned items with the system prompt).
enum Trash {
    @discardableResult
    static func move(_ path: String) async -> Bool {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) || (try? url.checkResourceIsReachable()) == true else { return true }
        do {
            _ = try await NSWorkspace.shared.recycle([url])
            return true
        } catch {
            return false
        }
    }
}

/// File metadata helpers used to enrich Mole's listings.
nonisolated enum FileInfo {
    static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func added(_ path: String) -> Date? {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate
    }

    /// Allocated size of a file or directory tree.
    static func allocatedSize(_ path: String) -> Double {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if values.isDirectory != true {
            return Double(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var total: Double = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        while let item = e?.nextObject() as? URL {
            if let v = try? item.resourceValues(forKeys: Set(keys)) {
                total += Double(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
