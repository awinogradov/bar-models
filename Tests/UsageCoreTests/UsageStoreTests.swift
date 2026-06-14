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
        let store = UsageStore(scanner: emptyScanner(), limitSource: source)
        await store.refresh()
        #expect(store.snapshot?.limit5h.isOfficial == true)
        #expect(abs((store.snapshot?.limit5h.percent ?? -1) - 0.42) < 1e-9)
    }

    @Test("a stale snapshot leaves limits non-official")
    @MainActor
    func staleOfficial() async throws {
        let source = try snapshotSource(fiveHour: 42, ageSeconds: 10_000, freshness: 900)
        let store = UsageStore(scanner: emptyScanner(), limitSource: source)
        await store.refresh()
        #expect(store.snapshot?.limit5h.isOfficial == false)
    }
}
