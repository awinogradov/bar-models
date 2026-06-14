import Foundation

/// How close usage is to a plan limit, for one window (5-hour or weekly).
///
/// `isOfficial` distinguishes the exact value from Claude Code's status line (M4)
/// from the calibrated estimate. `available == false` means there isn't enough
/// to show a number yet (no history, no official snapshot) → render `—`.
public struct LimitStatus: Sendable, Equatable {
    /// 0...1 typically; may exceed 1 when the window is over budget.
    public var percent: Double
    public var isOfficial: Bool
    public var available: Bool
    /// Short provenance for the dropdown, e.g. "est · P90 of 312 blocks" / "official".
    public var basis: String

    public init(percent: Double = 0, isOfficial: Bool = false, available: Bool = false, basis: String = "—") {
        self.percent = percent
        self.isOfficial = isOfficial
        self.available = available
        self.basis = basis
    }
}
