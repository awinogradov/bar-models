import Testing
import Foundation
@testable import UsageCore

@Suite("UsageStore")
struct UsageStoreTests {
    @Test("starts empty and idle")
    @MainActor
    func startsEmpty() {
        let store = UsageStore()
        #expect(store.snapshot == nil)
        #expect(store.isScanning == false)
    }

    /// An empty registry means no real `~/.claude` scan — deterministic and fast.
    private func emptyScanner() -> UsageScanner {
        UsageScanner(registry: ProviderRegistry(providers: []))
    }

    private func snapshotSource(fiveHour: Double, ageSeconds: TimeInterval, freshness: TimeInterval) throws -> LimitSource {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("snapshot.json")
        let ts = Date().timeIntervalSince1970 - ageSeconds
        try "{\"five_hour\": \(fiveHour), \"ts\": \(ts)}".write(to: url, atomically: true, encoding: .utf8)
        return LimitSource(url: url, freshness: freshness)
    }

    @Test("a fresh official snapshot publishes official limits")
    @MainActor
    func freshOfficial() async throws {
        let source = try snapshotSource(fiveHour: 42, ageSeconds: 0, freshness: 15 * 60)
        let store = UsageStore(scanner: emptyScanner(), limitSource: source, scanStateStore: nil)
        await store.refresh()
        #expect(store.snapshot?.limit5h.isOfficial == true)
        #expect(abs((store.snapshot?.limit5h.percent ?? -1) - 0.42) < 1e-9)
    }

    @Test("a stale snapshot leaves limits non-official")
    @MainActor
    func staleOfficial() async throws {
        let source = try snapshotSource(fiveHour: 42, ageSeconds: 10_000, freshness: 900)
        let store = UsageStore(scanner: emptyScanner(), limitSource: source, scanStateStore: nil)
        await store.refresh()
        #expect(store.snapshot?.limit5h.isOfficial == false)
    }

    @Test("a persisted scan state seeds the first scan (off-main load)")
    @MainActor
    func seedsFromPersistedState() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = ScanStateStore(url: dir.appendingPathComponent("scan-state.json"))

        // Pre-seed the cache; an empty registry means no real ~/.claude scan, so the
        // published snapshot reflects exactly the persisted event — proving load seeded it.
        persistence.save(ScanState(events: ["claude\u{1}seed": UsageEvent(
            id: "seed", provider: .claude, timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            model: "claude-opus-4-8", tokens: TokenCounts(input: 1_000, output: 0))]), now: Date())

        let store = UsageStore(scanner: emptyScanner(), scanStateStore: persistence)
        await store.refresh()
        #expect(store.snapshot?.eventCount == 1)
    }
}
