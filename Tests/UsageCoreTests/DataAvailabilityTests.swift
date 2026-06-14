import Testing
@testable import UsageCore

@Suite("DataAvailability")
struct DataAvailabilityTests {
    private func snapshot(eventCount: Int) -> UsageSnapshot {
        UsageSnapshot(generatedAt: .distantPast, eventCount: eventCount, totals: [:])
    }

    @Test("nil snapshot is loading, regardless of sources")
    func loadingBeforeFirstScan() {
        #expect(DataAvailability(snapshot: nil, hasDataSources: false) == .loading)
        #expect(DataAvailability(snapshot: nil, hasDataSources: true) == .loading)
    }

    @Test("no data roots and no events is noSource")
    func noSourceWhenRootsMissing() {
        #expect(DataAvailability(snapshot: snapshot(eventCount: 0), hasDataSources: false) == .noSource)
    }

    @Test("data roots present but zero events is empty")
    func emptyWhenRootsButNoEvents() {
        #expect(DataAvailability(snapshot: snapshot(eventCount: 0), hasDataSources: true) == .empty)
    }

    @Test("any events makes it ready, even with no recorded source")
    func readyWhenEventsPresent() {
        #expect(DataAvailability(snapshot: snapshot(eventCount: 1), hasDataSources: true) == .ready)
        #expect(DataAvailability(snapshot: snapshot(eventCount: 42), hasDataSources: false) == .ready)
    }
}
