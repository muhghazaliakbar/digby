import Foundation
import Observation
import SwiftUI

/// Shared ring buffer (last 500 lines) backing the bottom Terminal drawer.
@Observable
final class TerminalLog {
    enum Kind: Sendable {
        case cmd, ok, warn, dim, def

        var color: Color {
            switch self {
            case .cmd: DS.accentLight
            case .ok: DS.success
            case .warn: DS.warning
            case .dim: DS.textFaint
            case .def: DS.textSecondary
            }
        }
    }

    struct Line: Identifiable, Equatable {
        let id: Int
        let text: String
        let kind: Kind
    }

    static let capacity = 500
    private(set) var lines: [Line] = []
    private var nextID = 0

    func log(_ text: String, _ kind: Kind = .def) {
        nextID += 1
        let prefix = kind == .cmd ? "$ " : "  "
        lines.append(Line(id: nextID, text: prefix + text, kind: kind))
        if lines.count > Self.capacity { lines.removeFirst(lines.count - Self.capacity) }
    }

    /// Streams a raw CLI line, tagging it by Mole's status glyphs.
    func stream(_ line: OutputLine) {
        log(line.text.trimmingCharacters(in: .whitespaces), Self.classify(line))
    }

    func clear() { lines.removeAll() }

    nonisolated static func classify(_ line: OutputLine) -> Kind {
        let t = line.text.trimmingCharacters(in: .whitespaces)
        if line.isError { return .warn }
        if t.hasPrefix("✓") || t.hasPrefix("✔") { return .ok }
        if t.hasPrefix("◎") || t.hasPrefix("⚠") || t.hasPrefix("✗") || t.hasPrefix("✘") || t.lowercased().hasPrefix("error") { return .warn }
        if t.hasPrefix("⊙") || t.hasPrefix("↳") || t.hasPrefix("=") || t.hasPrefix("-") { return .dim }
        return .def
    }
}
