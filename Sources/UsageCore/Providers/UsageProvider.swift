import Foundation

/// The extensibility seam. Everything provider-specific — where data lives, how
/// to parse a record, the pricing table — is isolated behind this protocol.
/// `ClaudeProvider` is the first implementation; Codex/Gemini are added later as
/// new types with no changes to the aggregation, metric, or rendering layers.
///
/// (A `limitSource` requirement for official rate-limit % is added in M4.)
public protocol UsageProvider: Sendable {
    /// Stable identifier, used to tag events and scope the menu.
    var id: ProviderID { get }

    /// Human-readable name, e.g. "Claude Code".
    var displayName: String { get }

    /// Directories that contain this provider's usage transcripts.
    /// Implementations must existence-check and return only roots that exist.
    func dataRoots() -> [URL]

    /// Parse a single transcript line into a normalized event, or `nil` if the
    /// line carries no usable usage (wrong record type, zero tokens, missing id,
    /// or unparseable). Must never throw — bad lines are skipped, not fatal.
    func parse(line: Data) -> UsageEvent?

    /// Per-model price table used for cost estimation.
    var pricing: PricingTable { get }
}
