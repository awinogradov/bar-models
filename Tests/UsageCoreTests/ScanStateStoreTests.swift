import Testing
import Foundation
@testable import UsageCore

@Suite("ScanStateStore")
struct ScanStateStoreTests {
    private func cacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("scanstore-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("scan-state.json")
    }

    private func event(_ id: String) -> UsageEvent {
        UsageEvent(id: id, provider: .claude, timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                   model: "claude-opus-4-8", tokens: TokenCounts(input: 5, output: 6))
    }

    private func sampleState(filePath: String) -> ScanState {
        ScanState(
            files: [filePath: FileScanState(size: 50, modified: 1.0, offset: 40, inode: 7, createdAt: 2.0)],
            events: ["\(ProviderID.claude.rawValue)\u{1}m1": event("m1")]
        )
    }

    @Test("save then load round-trips the state")
    func roundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let backing = dir.appendingPathComponent("a.jsonl")
        try Data("x".utf8).write(to: backing) // a real file so the existence prune keeps the cursor

        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ScanStateStore(url: url)
        let state = sampleState(filePath: backing.path)

        store.save(state, now: Date())
        #expect(store.load(now: Date()) == state)
    }

    @Test("corrupt bytes load as nil")
    func corrupt() throws {
        let url = cacheURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("{ not json".utf8).write(to: url)
        #expect(ScanStateStore(url: url).load(now: Date()) == nil)
    }

    @Test("a wrong schema version loads as nil")
    func wrongVersion() throws {
        let url = cacheURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data(#"{"version":999,"savedAt":0,"state":{"files":{},"events":{}}}"#.utf8).write(to: url)
        #expect(ScanStateStore(url: url).load(now: Date(timeIntervalSince1970: 1)) == nil)
    }

    @Test("a cache older than maxAge loads as nil, but a fresh one loads")
    func stale() {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ScanStateStore(url: url, maxAge: 60)
        store.save(ScanState(), now: Date(timeIntervalSince1970: 1_000))
        #expect(store.load(now: Date(timeIntervalSince1970: 1_061)) == nil)   // 61s old → discarded
        #expect(store.load(now: Date(timeIntervalSince1970: 1_059)) != nil)   // 59s old → kept
    }

    @Test("a missing file loads as nil")
    func missing() {
        #expect(ScanStateStore(url: cacheURL()).load(now: Date()) == nil)
    }

    @Test("a cursor for a since-deleted file is pruned on load; its events remain")
    func prunesMissingFileCursor() throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ScanStateStore(url: url)
        store.save(sampleState(filePath: "/no/such/file-\(UUID().uuidString).jsonl"), now: Date())
        let loaded = try #require(store.load(now: Date()))
        #expect(loaded.files.isEmpty)     // cursor for the vanished file pruned
        #expect(loaded.events.count == 1) // events kept (id-keyed, idempotent on re-read)
    }
}
