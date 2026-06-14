import Testing
import Foundation
@testable import UsageCore

@Suite("Plan limits")
struct LimitTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func event(at offset: TimeInterval, billable: UInt64) -> UsageEvent {
        UsageEvent(id: UUID().uuidString, provider: .claude,
                   timestamp: base.addingTimeInterval(offset),
                   model: "claude-opus-4-8", tokens: TokenCounts(cacheRead: billable))
    }

    @Test("blocks split on the 5-hour boundary")
    func blocks() {
        let b = FiveHourWindower().blocks([
            event(at: 0, billable: 10),
            event(at: 3600, billable: 20),       // within 5h of the first → same block
            event(at: 6 * 3600, billable: 5),    // > 5h after start → new block
        ])
        #expect(b.count == 2)
        #expect(b[0].usage == 30)
        #expect(b[1].usage == 5)
    }

    @Test("p90 picks the 90th percentile")
    func p90() {
        #expect(LimitEstimator.p90(Array(1...10).map(UInt64.init)) == 9) // idx round(9*0.9)=8 → 9
        #expect(LimitEstimator.p90([]) == nil)
    }

    @Test("5h estimate = active block ÷ P90 of blocks")
    func fiveHour() {
        let now = base.addingTimeInterval(100 * 3600)
        let status = LimitEstimator().fiveHour([
            event(at: 0, billable: 100),                       // old block
            event(at: 100 * 3600 - 3600, billable: 50),        // active block (within 5h of now)
        ], now: now)
        #expect(status.available)
        #expect(abs(status.percent - 0.5) < 1e-9) // 50 / P90([100,50]) = 50/100
        #expect(!status.isOfficial)
    }

    @Test("weekly estimate = rolling 7-day ÷ P90 of weekly load")
    func weekly() {
        let now = base.addingTimeInterval(30 * 86_400)
        let status = LimitEstimator().weekly([
            event(at: 10 * 86_400, billable: 1000),            // outside the trailing 7 days
            event(at: 30 * 86_400 - 86_400, billable: 300),    // inside the trailing 7 days
        ], now: now)
        #expect(status.available)
        #expect(abs(status.percent - 0.3) < 1e-9) // 300 / P90([1000,300]) = 300/1000
    }

    @Test("custom budget overrides the estimate")
    func customBudget() {
        let now = base.addingTimeInterval(3600)
        let status = LimitEstimator().fiveHour([event(at: 0, billable: 50)], now: now, customBudget: 200)
        #expect(abs(status.percent - 0.25) < 1e-9)
        #expect(status.basis.contains("custom"))
    }

    @Test("no events ⇒ unavailable")
    func empty() {
        #expect(!LimitEstimator().fiveHour([], now: base).available)
        #expect(!LimitEstimator().weekly([], now: base).available)
    }
}
