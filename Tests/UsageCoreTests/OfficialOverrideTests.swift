import Testing
import Foundation
@testable import UsageCore

@Suite("Official limit override")
struct OfficialOverrideTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private var now: Date { base.addingTimeInterval(3600) }

    /// One recent event → both estimates are available (isOfficial == false).
    private var events: [UsageEvent] {
        [UsageEvent(id: "e1", provider: .claude, timestamp: base,
                    model: "claude-opus-4-8", tokens: TokenCounts(cacheRead: 100))]
    }

    private func aggregate(official: OfficialLimits = OfficialLimits()) -> UsageSnapshot {
        Aggregator().aggregate(events, using: PeriodBucketer(zone: .utc, now: now), official: official)
    }

    @Test("an official window supersedes the estimate; the other window stays estimated")
    func overridesPerWindow() {
        let official = OfficialLimits(
            fiveHour: LimitStatus(percent: 0.5, isOfficial: true, available: true, basis: "official"))
        let snap = aggregate(official: official)
        #expect(snap.limit5h.isOfficial == true)
        #expect(snap.limit5h.percent == 0.5)
        #expect(snap.limitWeekly.isOfficial == false) // no official weekly → estimate retained
        #expect(snap.limitWeekly.available == true)
    }

    @Test("no official data leaves both windows on the estimate")
    func noOfficial() {
        let snap = aggregate()
        #expect(snap.limit5h.isOfficial == false)
        #expect(snap.limitWeekly.isOfficial == false)
    }

    @Test("a stale snapshot read by LimitSource falls back to the estimate, not —")
    func staleFallsBackToEstimate() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("override-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("snapshot.json")
        // ts well beyond the freshness window → LimitSource yields empty.
        let staleTs = now.timeIntervalSince1970 - 10_000
        try "{\"five_hour\": 90, \"seven_day\": 90, \"ts\": \(staleTs)}"
            .write(to: url, atomically: true, encoding: .utf8)

        let official = LimitSource(url: url, freshness: 900).read(now: now)
        #expect(official == OfficialLimits())

        let snap = aggregate(official: official)
        #expect(snap.limit5h.isOfficial == false)
        #expect(snap.limit5h.available == true) // estimate, not unavailable
    }
}
