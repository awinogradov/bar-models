import Testing
import Foundation
@testable import UsageCore

@Suite("MetricSelection")
struct MetricSelectionTests {
    private func snapshot() -> UsageSnapshot {
        UsageSnapshot(generatedAt: .distantPast, eventCount: 1, totals: [
            .thisMonth: PeriodTotals(tokens: TokenCounts(input: 1_000_000, output: 200_000, cacheWrite: 50_000, cacheRead: 9_000_000)),
            .today: PeriodTotals(tokens: TokenCounts(input: 500, output: 300)),
        ])
    }

    @Test("renders tokens per definition")
    func tokensByDefinition() {
        let s = snapshot()
        var sel = MetricSelection(metric: .tokens, period: .thisMonth, tokenDefinition: .inputOutputOnly)
        #expect(sel.render(from: s) == "1.2M") // 1,200,000

        sel.tokenDefinition = .billableTotal
        #expect(sel.render(from: s) == UsageFormat.tokens(s.tokens(.thisMonth).billableTotal))
    }

    @Test("period switch changes the rendered value")
    func periodSwitch() {
        let s = snapshot()
        #expect(MetricSelection(metric: .tokens, period: .today).render(from: s) == "800") // 500+300
        #expect(MetricSelection(metric: .tokens, period: .thisMonth).render(from: s) == "1.2M")
    }

    @Test("labels and headers")
    func labelsHeaders() {
        #expect(MetricSelection(metric: .tokens, period: .today).label == "Tokens — Today")
        #expect(MetricSelection(metric: .cost, period: .thisMonth).header == "Cost · This Month")
        #expect(MetricSelection(metric: .limit5h).label == "Plan limit — 5h")
    }

    @Test("limits are placeholders until M4; cost renders")
    func placeholders() {
        let s = snapshot()
        #expect(MetricSelection(metric: .limit5h).render(from: s) == "—")
        #expect(MetricSelection(metric: .limitWeekly).render(from: s) == "—")
        // Cost now renders; the hand-built snapshot has no baked cost ⇒ $0.00.
        #expect(MetricSelection(metric: .cost, period: .thisMonth).render(from: s) == "$0.00")
    }

    @Test("nil snapshot renders the loading glyph")
    func nilSnapshot() {
        #expect(MetricSelection().render(from: nil) == "…")
    }

    @Test("round-trips through its JSON string representation")
    func jsonRoundTrip() {
        let sel = MetricSelection(metric: .tokens, period: .rolling7, tokenDefinition: .billableTotal)
        #expect(MetricSelection(jsonString: sel.jsonString) == sel)
        #expect(MetricSelection(jsonString: "not json") == nil)
    }
}
