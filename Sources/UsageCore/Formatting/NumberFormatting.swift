import Foundation

/// Compact, glanceable number formatting for the menu bar.
public enum UsageFormat {
    /// Abbreviated token count: `999`, `1.5K`, `38.2M`, `2.5B`.
    public static func tokens(_ n: UInt64) -> String {
        switch n {
        case 0..<1_000: "\(n)"
        case 1_000..<1_000_000: trimmed(Double(n) / 1_000) + "K"
        case 1_000_000..<1_000_000_000: trimmed(Double(n) / 1_000_000) + "M"
        default: trimmed(Double(n) / 1_000_000_000) + "B"
        }
    }

    /// Exact, grouped count for the dropdown: `38,214,556`.
    public static func grouped(_ n: UInt64) -> String {
        n.formatted(.number.grouping(.automatic))
    }

    private static func trimmed(_ x: Double) -> String {
        let s = String(format: "%.1f", x)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}
