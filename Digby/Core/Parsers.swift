import Foundation

// Parsers for Mole's output. Each one is pure and covered by DigbyTests.

nonisolated enum SizeParser {
    private static let regex = try! NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s?(TB|GB|MB|KB|B)\b\+?"#)

    /// Parses Mole's `bytes_to_human` output (decimal units), e.g. `1.01GB`, `172KB`, `0B`.
    static func bytes(_ text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range),
              let numR = Range(m.range(at: 1), in: text),
              let unitR = Range(m.range(at: 2), in: text),
              let value = Double(text[numR]) else { return nil }
        switch text[unitR] {
        case "TB": return value * 1e12
        case "GB": return value * 1e9
        case "MB": return value * 1e6
        case "KB": return value * 1e3
        default: return value
        }
    }

    /// The last size token on a line (Mole prints the size after names that may contain digits).
    static func lastBytes(_ text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard let m = matches.last, let r = Range(m.range, in: text) else { return nil }
        return bytes(String(text[r]))
    }
}

// MARK: - mo clean

nonisolated enum CleanEvent: Equatable, Sendable {
    case section(String)
    case item(section: String, name: String, bytes: Double)
    case whitelist(String)
    case summary(bytes: Double, items: Int?)
}

nonisolated struct CleanParser {
    private(set) var section: String?
    private var inWhitelist = false

    /// Status glyphs Mole prints before cleanable items (dry run uses → , real runs use ✓).
    static let itemGlyphs: [Character] = ["→", "✓", "✔"]

    mutating func feed(_ raw: String) -> CleanEvent? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard let first = line.first else { return nil }

        if line.hasPrefix("➤") {
            inWhitelist = false
            let name = line.dropFirst().trimmingCharacters(in: .whitespaces)
            section = name
            return .section(name)
        }
        if line.contains("Whitelist:") && line.contains("pattern") {
            inWhitelist = true
            return nil
        }
        if inWhitelist {
            if line.hasPrefix("↳") {
                let path = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if path.hasPrefix("/") { return .whitelist(path) }
                return nil
            }
            inWhitelist = false
        }
        if let summary = Self.summary(line) { return summary }
        guard let section, Self.itemGlyphs.contains(first) else { return nil }

        let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
        guard let bytes = SizeParser.lastBytes(body) else { return nil }
        let name = Self.itemName(body)
        guard !name.isEmpty else { return nil }
        return .item(section: section, name: name, bytes: bytes)
    }

    static func itemName(_ body: String) -> String {
        var name = body
        if let r = name.range(of: " · ") { name = String(name[..<r.lowerBound]) }
        if let r = name.range(of: ", would clean") { name = String(name[..<r.lowerBound]) }
        if let r = name.range(of: ", ") { name = String(name[..<r.lowerBound]) }
        return name.trimmingCharacters(in: .whitespaces)
    }

    static func summary(_ line: String) -> CleanEvent? {
        let keys = ["Potential space:", "Tracked cleanup:", "Space freed:", "Total freed:", "Freed:"]
        guard let key = keys.first(where: { line.hasPrefix($0) }) else { return nil }
        let rest = String(line.dropFirst(key.count))
        guard let bytes = SizeParser.bytes(rest) else { return nil }
        var items: Int?
        if let r = rest.range(of: #"Items(?: cleaned)?: ([0-9,]+)"#, options: .regularExpression) {
            let digits = rest[r].filter(\.isNumber)
            items = Int(digits)
        }
        return .summary(bytes: bytes, items: items)
    }
}

/// Parses `~/.config/mole/clean-list.txt`, the per-path preview `mo clean --dry-run` writes.
nonisolated enum CleanListParser {
    struct Entry: Equatable, Sendable {
        var path: String
        var bytes: Double
    }

    struct Section: Equatable, Sendable {
        var name: String
        var entries: [Entry]
    }

    static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/mole/clean-list.txt")
    }

    static func parse(_ text: String) -> [Section] {
        var sections: [Section] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("===") && line.hasSuffix("===") {
                let name = line.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
                sections.append(Section(name: name, entries: []))
                continue
            }
            guard line.hasPrefix("/") || line.hasPrefix("~"), !sections.isEmpty else { continue }
            guard let hash = line.range(of: "  # ") ?? line.range(of: " # ") else { continue }
            let meta = String(line[hash.upperBound...])
            if meta.contains("counted under") { continue }
            let path = line[..<hash.lowerBound].trimmingCharacters(in: .whitespaces)
            let bytes = SizeParser.bytes(meta) ?? 0
            sections[sections.count - 1].entries.append(Entry(path: path, bytes: bytes))
        }
        return sections.filter { !$0.entries.isEmpty }
    }
}

// MARK: - mo purge

nonisolated enum PurgeParser {
    struct Item: Equatable, Sendable {
        var path: String
        var bytes: Double
    }

    /// `✓ [DRY RUN] ~/code/app/node_modules, 1.24GB`
    static func item(_ raw: String) -> Item? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        guard let first = line.first, ["✓", "✔", "→", "•"].contains(first) else { return nil }
        line = line.dropFirst().trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("[DRY RUN]") { line = line.dropFirst(9).trimmingCharacters(in: .whitespaces) }
        guard line.hasPrefix("~") || line.hasPrefix("/"),
              let comma = line.range(of: ", ", options: .backwards) else { return nil }
        let path = String(line[..<comma.lowerBound])
        guard let bytes = SizeParser.bytes(String(line[comma.upperBound...])) else { return nil }
        return Item(path: path, bytes: bytes)
    }
}

// MARK: - mo installer

nonisolated enum InstallerParser {
    struct Item: Equatable, Sendable {
        var displayName: String
        var bytes: Double
        var source: String
    }

    private static let regex = try! NSRegularExpression(
        pattern: #"[○●◉]\s+(.+?)\s+([0-9]+(?:\.[0-9]+)?(?:TB|GB|MB|KB|B))\s*\|\s*(.+?)\s*$"#
    )

    /// One row of the installer selector: `○ Docker.dmg     620.0MB | Downloads`.
    static func item(_ raw: String) -> Item? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        let range = NSRange(line.startIndex..., in: line)
        guard let m = regex.firstMatch(in: line, range: range),
              let n = Range(m.range(at: 1), in: line),
              let s = Range(m.range(at: 2), in: line),
              let src = Range(m.range(at: 3), in: line),
              let bytes = SizeParser.bytes(String(line[s])) else { return nil }
        return Item(displayName: String(line[n]).trimmingCharacters(in: .whitespaces),
                    bytes: bytes,
                    source: String(line[src]).trimmingCharacters(in: .whitespaces))
    }

    /// Directories Mole reports as installer sources.
    static func directories(for source: String) -> [String] {
        let home = NSHomeDirectory()
        switch source.lowercased() {
        case "downloads": return [home + "/Downloads"]
        case "desktop": return [home + "/Desktop"]
        case "documents": return [home + "/Documents"]
        case "homebrew": return [home + "/Library/Caches/Homebrew/downloads", home + "/Library/Caches/Homebrew/Cask", home + "/Library/Caches/Homebrew"]
        case "icloud": return [home + "/Library/Mobile Documents/com~apple~CloudDocs", home + "/Library/Mobile Documents/com~apple~CloudDocs/Downloads"]
        case "mail": return [home + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"]
        case "telegram": return [home + "/Downloads/Telegram Desktop", home + "/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram"]
        default: return [home + "/Downloads", home + "/Desktop"]
        }
    }

    /// Resolves a (possibly `...`-truncated) display name to a real file path.
    static func resolve(_ item: Item, fileManager fm: FileManager = .default) -> String? {
        let truncated = item.displayName.hasSuffix("...")
        let prefix = truncated ? String(item.displayName.dropLast(3)) : item.displayName
        for dir in directories(for: item.source) + directories(for: "") {
            if !truncated {
                let p = dir + "/" + item.displayName
                if fm.fileExists(atPath: p) { return p }
            }
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            let candidates = names.filter { $0.hasPrefix(prefix) || $0.hasSuffix("--" + item.displayName) || (truncated && $0.contains(prefix)) }
            if candidates.count == 1 { return dir + "/" + candidates[0] }
            if let best = candidates.min(by: { abs(sizeOf(dir + "/" + $0) - item.bytes) < abs(sizeOf(dir + "/" + $1) - item.bytes) }) {
                return dir + "/" + best
            }
        }
        return nil
    }

    private static func sizeOf(_ path: String) -> Double {
        Double((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0)
    }
}

// MARK: - mo optimize

nonisolated enum OptimizeEvent: Equatable, Sendable {
    case section(String)
    case detail(String)
    case finished
}

nonisolated enum OptimizeParser {
    static func event(_ raw: String) -> OptimizeEvent? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("➤") { return .section(line.dropFirst().trimmingCharacters(in: .whitespaces)) }
        if line.lowercased().hasPrefix("optimization complete") || line.lowercased().hasPrefix("dry run complete") { return .finished }
        if let f = line.first, ["→", "✓", "◎", "⚠", "-", "⊙", "✗"].contains(f) {
            return .detail(line.dropFirst().trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

// MARK: - JSON payloads

nonisolated struct StatusSnapshot: Decodable, Sendable {
    struct Hardware: Decodable, Sendable { var model: String?; var cpu_model: String?; var total_ram: String?; var disk_size: String?; var os_version: String? }
    struct CPU: Decodable, Sendable { var usage: Double?; var per_core: [Double]?; var p_core_count: Int?; var e_core_count: Int?; var logical_cpu: Int?; var load1: Double? }
    struct Memory: Decodable, Sendable { var used: Double?; var total: Double?; var available: Double?; var used_percent: Double?; var swap_used: Double?; var swap_total: Double?; var cached: Double?; var pressure: String? }
    struct Disk: Decodable, Sendable { var mount: String?; var used: Double?; var total: Double?; var external: Bool? }
    struct DiskIO: Decodable, Sendable { var read_rate: Double?; var write_rate: Double? }
    struct Net: Decodable, Sendable { var name: String?; var rx_rate_mbs: Double?; var tx_rate_mbs: Double?; var ip: String? }
    struct NetHistory: Decodable, Sendable { var rx_history: [Double]?; var tx_history: [Double]? }
    struct Battery: Decodable, Sendable { var percent: Double?; var status: String?; var time_left: String?; var health: String?; var cycle_count: Int?; var capacity: Double? }
    struct Thermal: Decodable, Sendable { var cpu_temp: Double?; var battery_temp: Double?; var adapter_power: Double?; var battery_power: Double? }
    struct Proc: Decodable, Sendable { var pid: Int?; var name: String?; var cpu: Double?; var memory: Double?; var memory_bytes: Double? }

    var host: String?
    var uptime: String?
    var uptime_seconds: Double?
    var hardware: Hardware?
    var health_score: Int?
    var health_score_msg: String?
    var cpu: CPU?
    var memory: Memory?
    var disks: [Disk]?
    var disk_io: DiskIO?
    var network: [Net]?
    var network_history: NetHistory?
    var batteries: [Battery]?
    var thermal: Thermal?
    var top_processes: [Proc]?

    static func decode(_ data: Data) -> StatusSnapshot? {
        try? JSONDecoder().decode(StatusSnapshot.self, from: data)
    }

    /// Receive / transmit rate in MB/s, preferring the routed interface history.
    var networkRates: (down: Double, up: Double) {
        if let rx = network_history?.rx_history?.last, let tx = network_history?.tx_history?.last { return (rx, tx) }
        let ifaces = (network ?? []).filter { !($0.name ?? "").hasPrefix("utun") }
        return (ifaces.reduce(0) { $0 + ($1.rx_rate_mbs ?? 0) }, ifaces.reduce(0) { $0 + ($1.tx_rate_mbs ?? 0) })
    }
}

nonisolated struct AnalyzeReport: Decodable, Sendable {
    struct Entry: Decodable, Sendable, Hashable {
        var name: String
        var path: String
        var size: Double
        var is_dir: Bool?
        var scan_status: String?
    }

    var path: String
    var entries: [Entry]?
    var total_size: Double?
    var scan_status: String?

    static func decode(_ data: Data) -> AnalyzeReport? {
        guard let start = data.firstIndex(of: UInt8(ascii: "{")) else { return nil }
        return try? JSONDecoder().decode(AnalyzeReport.self, from: data[start...])
    }
}

nonisolated struct ListedApp: Decodable, Sendable, Equatable {
    var name: String
    var bundle_id: String?
    var source: String?
    var uninstall_name: String?
    var path: String

    /// Decodes `mo` app inventory JSON, skipping malformed rows instead of failing the whole list.
    static func decodeList(_ data: Data) -> [ListedApp] {
        guard let start = data.firstIndex(of: UInt8(ascii: "[")) else { return [] }
        let slice = data[start...]
        if let apps = try? JSONDecoder().decode([ListedApp].self, from: slice) { return apps }
        let text = String(decoding: slice, as: UTF8.self)
        return text.split(separator: "\n").compactMap { row in
            var s = row.trimmingCharacters(in: .whitespaces)
            if s.hasSuffix(",") { s.removeLast() }
            guard s.hasPrefix("{") else { return nil }
            return try? JSONDecoder().decode(ListedApp.self, from: Data(s.utf8))
        }
    }
}
