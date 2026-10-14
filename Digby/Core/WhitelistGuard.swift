import Foundation

/// `mo clean` has no per-path selection flag; it skips anything in `~/.config/mole/whitelist`.
/// To honour unchecked rows, Digby appends them to the whitelist for the duration of one run
/// and restores the user's file afterwards (also on next launch if the app quit mid-run).
nonisolated enum WhitelistGuard {
    /// Mole's config folder. `-moleConfigDir <path>` overrides it (used by the UI tests' fake `mo`).
    static var directory: URL {
        if let custom = UserDefaults.standard.string(forKey: "moleConfigDir"), !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/mole")
    }
    static var file: URL { directory.appendingPathComponent("whitelist") }
    static var backup: URL { directory.appendingPathComponent(".digby-whitelist-backup") }
    static var marker: URL { directory.appendingPathComponent(".digby-whitelist-marker") }

    static let beginMarker = "# >>> Digby temporary exclusions (restored automatically)"
    static let endMarker = "# <<< Digby"

    /// Builds the temporary whitelist. When the user has no file, Mole's active defaults
    /// (as printed by the scan) are kept so creating the file does not drop them.
    static func contents(original: String?, defaults: [String], exclusions: [String]) -> String {
        var lines: [String] = []
        if let original {
            lines.append(original.trimmingCharacters(in: .newlines))
        } else {
            lines.append("# Mole defaults, kept by Digby while it excludes unchecked items")
            lines.append(contentsOf: defaults)
        }
        lines.append(beginMarker)
        lines.append(contentsOf: exclusions.filter(isSafe))
        lines.append(endMarker)
        return lines.joined(separator: "\n") + "\n"
    }

    static func isSafe(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains("..") && !path.contains("//") && path.rangeOfCharacter(from: .controlCharacters) == nil
    }

    static func apply(defaults: [String], exclusions: [String]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let existed = fm.fileExists(atPath: file.path)
        let original = existed ? try String(contentsOf: file, encoding: .utf8) : nil
        if existed {
            if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
            try fm.copyItem(at: file, to: backup)
        }
        try (existed ? "present" : "absent").write(to: marker, atomically: true, encoding: .utf8)
        try contents(original: original, defaults: defaults, exclusions: exclusions)
            .write(to: file, atomically: true, encoding: .utf8)
    }

    /// Puts the user's whitelist back exactly as it was before `apply`.
    static func restore() {
        let fm = FileManager.default
        guard let state = try? String(contentsOf: marker, encoding: .utf8) else { return }
        if state.hasPrefix("present") {
            if fm.fileExists(atPath: backup.path) {
                _ = try? fm.replaceItemAt(file, withItemAt: backup)
            }
        } else if fm.fileExists(atPath: file.path) {
            // Digby created this file for the run; the user had none.
            try? fm.removeItem(at: file)
        }
        try? fm.removeItem(at: marker)
    }

    static func restoreIfNeeded() {
        if FileManager.default.fileExists(atPath: marker.path) { restore() }
    }
}
