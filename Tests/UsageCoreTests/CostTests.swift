import Testing
import Foundation
@testable import UsageCore

@Suite("Cost")
struct CostTests {
    @Test("prices each model on its own rates and sums")
    func breakdown() {
        let byModel: [String: TokenCounts] = [
            "claude-opus-4-8": TokenCounts(output: 1_000_000),  // 1M output × $25 = $25
            "claude-haiku-4-5": TokenCounts(input: 2_000_000),  // 2M input × $1 = $2
        ]
        let b = CostCalculator(pricing: .claude).cost(of: byModel)
        #expect(b.byModel["claude-opus-4-8"] == 25.0)
        #expect(b.byModel["claude-haiku-4-5"] == 2.0)
        #expect(b.total == 27.0)
        #expect(b.unknownModelTokens == 0)
    }

    @Test("unpriced models are flagged, not zeroed into the total")
    func unknown() {
        let b = CostCalculator(pricing: .claude).cost(of: ["<synthetic>": TokenCounts(input: 5, output: 5)])
        #expect(b.total == 0)
        #expect(b.byModel.isEmpty)
        #expect(b.unknownModelTokens == 10)
    }

    @Test("aggregator bakes cost into the snapshot")
    func aggregated() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 22, hour: 12))!
        let event = UsageEvent(id: "x", provider: .claude, timestamp: now,
                               model: "claude-opus-4-8", tokens: TokenCounts(output: 1_000_000))
        let snap = Aggregator().aggregate([event], using: PeriodBucketer(zone: .utc, now: now))
        #expect(snap.totals(for: .today).cost == 25.0)
        #expect(snap.totals(for: .today).unknownModelTokens == 0)
    }

    @Test("currency formatting")
    func formatting() {
        #expect(UsageFormat.cost(4.42) == "$4.42")
        #expect(UsageFormat.cost(4419.37) == "$4.4K")
        #expect(UsageFormat.cost(1_500_000) == "$1.5M")
    }
}
