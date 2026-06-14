import Foundation

/// What kind of number is shown.
public enum Metric: String, Sendable, Codable, CaseIterable {
    case tokens
    case cost        // M3
    case limit5h     // M4
    case limitWeekly // M4
}

/// The "one thing" — a single, switchable, persistable description of what the
/// menu bar displays. Rendering is pure (snapshot in, string out); cost and
/// plan-limit metrics render a placeholder until M3/M4 wire them up.
public struct MetricSelection: Codable, Equatable, Hashable, Sendable {
    public var provider: ProviderID
    public var metric: Metric
    public var period: Period
    public var tokenDefinition: TokenDefinition

    public init(
        provider: ProviderID = .claude,
        metric: Metric = .tokens,
        period: Period = .thisMonth,
        tokenDefinition: TokenDefinition = .inputOutputOnly
    ) {
        self.provider = provider
        self.metric = metric
        self.period = period
        self.tokenDefinition = tokenDefinition
    }

    public static let `default` = MetricSelection()

    /// Compact value for the menu bar and quick-switch rows.
    public func render(from snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return "…" }
        switch metric {
        case .tokens: return UsageFormat.tokens(snapshot.tokens(period).value(for: tokenDefinition))
        case .cost, .limit5h, .limitWeekly: return "—" // M3 / M4
        }
    }

    /// Exact, grouped value for the dropdown header.
    public func renderExact(from snapshot: UsageSnapshot?) -> String {
        guard let snapshot, metric == .tokens else { return "—" }
        return UsageFormat.grouped(snapshot.tokens(period).value(for: tokenDefinition))
    }

    /// Quick-switch row label, e.g. "Tokens — This Month".
    public var label: String {
        switch metric {
        case .tokens: "Tokens — \(period.label)"
        case .cost: "Cost — \(period.label)"
        case .limit5h: "Plan limit — 5h"
        case .limitWeekly: "Plan limit — Weekly"
        }
    }

    /// Dropdown header, e.g. "Tokens · This Month".
    public var header: String {
        switch metric {
        case .tokens: "Tokens · \(period.label)"
        case .cost: "Cost · \(period.label)"
        case .limit5h: "Plan limit · 5-hour"
        case .limitWeekly: "Plan limit · Weekly"
        }
    }
}

/// JSON string for persistence in a single `UserDefaults` key.
///
/// Deliberately **not** `RawRepresentable<String>`: the stdlib ships a `Codable`
/// default for `RawRepresentable where RawValue: Codable` that would shadow the
/// synthesized member-wise coding — encoding `self` would call `rawValue`, which
/// encodes `self` again → infinite recursion (a SIGBUS stack overflow). Keeping
/// the synthesized `Codable` and exposing plain helpers avoids the trap.
public extension MetricSelection {
    var jsonString: String {
        guard let data = try? JSONEncoder().encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(MetricSelection.self, from: data)
        else { return nil }
        self = decoded
    }
}
