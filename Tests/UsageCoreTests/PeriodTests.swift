import Testing
import Foundation
@testable import UsageCore

@Suite("Period bucketing & aggregation")
struct PeriodTests {
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    @Test("today and month membership")
    func todayAndMonth() {
        let b = PeriodBucketer(zone: .utc, now: date(2026, 5, 22))
        #expect(b.contains(date(2026, 5, 22, 1), in: .today))
        #expect(!b.contains(date(2026, 5, 21, 23), in: .today))
        #expect(b.contains(date(2026, 5, 1), in: .thisMonth))
        #expect(!b.contains(date(2026, 4, 30), in: .thisMonth))
    }

    @Test("rolling-30 boundary")
    func rolling30() {
        let b = PeriodBucketer(zone: .utc, now: date(2026, 5, 22))
        #expect(b.contains(date(2026, 5, 1), in: .rolling30))   // ~21 days ago
        #expect(!b.contains(date(2026, 4, 1), in: .rolling30))  // ~51 days ago
    }

    @Test("this-week membership is robust to firstWeekday")
    func thisWeek() {
        let b = PeriodBucketer(zone: .utc, now: date(2026, 5, 22, 12))
        #expect(b.contains(date(2026, 5, 22, 9), in: .thisWeek)) // same day ⇒ same week
        #expect(!b.contains(date(2026, 5, 1), in: .thisWeek))    // 3 weeks earlier
    }

    @Test("aggregate sums per period and per model")
    func aggregate() {
        let b = PeriodBucketer(zone: .utc, now: date(2026, 5, 22))
        let events = [
            UsageEvent(id: "a", provider: .claude, timestamp: date(2026, 5, 22, 1),
                       model: "claude-opus-4-8", tokens: TokenCounts(input: 10, output: 5)),
            UsageEvent(id: "b", provider: .claude, timestamp: date(2026, 5, 2),
                       model: "claude-sonnet-4-6", tokens: TokenCounts(input: 100, output: 50)),
            UsageEvent(id: "c", provider: .claude, timestamp: date(2026, 3, 1),
                       model: "claude-opus-4-8", tokens: TokenCounts(input: 7, output: 7)),
        ]
        let snap = Aggregator().aggregate(events, using: b)
        #expect(snap.tokens(.today).inputOutput == 15)      // a only
        #expect(snap.tokens(.thisMonth).inputOutput == 165) // a + b
        #expect(snap.eventCount == 3)
        #expect(snap.totals(for: .thisMonth).byModel["claude-opus-4-8"]?.inputOutput == 15)
    }
}
