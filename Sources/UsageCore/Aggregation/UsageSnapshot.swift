import Foundation

/// Aggregated totals for one period, with a per-model breakdown (used by cost in M3).
public struct PeriodTotals: Sendable, Equatable {
    public var tokens: TokenCounts
    public var byModel: [String: TokenCounts]
    /// Estimated USD cost for this period (computed by the `Aggregator`).
    public var cost: Double
    /// Billable tokens from models with no known price (flagged, excluded from `cost`).
    public var unknownModelTokens: UInt64

    public init(
        tokens: TokenCounts = .zero,
        byModel: [String: TokenCounts] = [:],
        cost: Double = 0,
        unknownModelTokens: UInt64 = 0
    ) {
        self.tokens = tokens
        self.byModel = byModel
        self.cost = cost
        self.unknownModelTokens = unknownModelTokens
    }
}

/// An immutable, `Sendable` rollup the UI binds to — computed off-main, handed to
/// the `@MainActor` store.
public struct UsageSnapshot: Sendable, Equatable {
    public let generatedAt: Date
    public let eventCount: Int
    public let totals: [Period: PeriodTotals]

    public init(generatedAt: Date, eventCount: Int, totals: [Period: PeriodTotals]) {
        self.generatedAt = generatedAt
        self.eventCount = eventCount
        self.totals = totals
    }

    public func totals(for period: Period) -> PeriodTotals { totals[period] ?? PeriodTotals() }
    public func tokens(_ period: Period) -> TokenCounts { totals(for: period).tokens }

    public static let empty = UsageSnapshot(generatedAt: .distantPast, eventCount: 0, totals: [:])
}
