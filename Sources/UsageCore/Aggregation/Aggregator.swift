import Foundation

/// Folds a flat event list into per-period (and per-model) totals in a single
/// pass. Periods overlap (today ⊂ thisWeek ⊂ thisMonth), so each event is tested
/// against every period in one loop.
public struct Aggregator: Sendable {
    public init() {}

    public func aggregate(
        _ events: [UsageEvent],
        using bucketer: PeriodBucketer,
        pricing: PricingTable = .claude
    ) -> UsageSnapshot {
        var totals: [Period: PeriodTotals] = [:]
        for period in Period.allCases { totals[period] = PeriodTotals() }

        for event in events {
            for period in Period.allCases where bucketer.contains(event.timestamp, in: period) {
                totals[period]!.tokens += event.tokens
                totals[period]!.byModel[event.model, default: .zero] += event.tokens
            }
        }

        let calculator = CostCalculator(pricing: pricing)
        for period in Period.allCases {
            let breakdown = calculator.cost(of: totals[period]!.byModel)
            totals[period]!.cost = breakdown.total
            totals[period]!.unknownModelTokens = breakdown.unknownModelTokens
        }

        return UsageSnapshot(generatedAt: bucketer.now, eventCount: events.count, totals: totals)
    }
}
