import Testing
import Foundation
@testable import UsageCore

@Suite("ScanState persistence")
struct ScanStatePersistenceTests {
    private func event(_ id: String, input: UInt64 = 1, model: String = "claude-opus-4-8") -> UsageEvent {
        UsageEvent(
            id: id,
            provider: .claude,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            model: model,
            tokens: TokenCounts(input: input, output: 2, cacheWrite: 3, cacheRead: 4)
        )
    }

    @Test("UsageEvent round-trips through Codable")
    func usageEventRoundTrip() throws {
        let original = event("msg_abc")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UsageEvent.self, from: data)
        #expect(decoded == original)
    }

    @Test("TokenCounts preserves full-range UInt64 exactly (no Double coercion)")
    func tokenCountsUInt64Fidelity() throws {
        let counts = TokenCounts(input: .max, output: 9_223_372_036_854_775_807, cacheWrite: 0, cacheRead: 1)
        let data = try JSONEncoder().encode(counts)
        let decoded = try JSONDecoder().decode(TokenCounts.self, from: data)
        #expect(decoded.input == .max)
        #expect(decoded.output == 9_223_372_036_854_775_807)
        #expect(decoded.cacheRead == 1)
        // The wire form must be a bare integer, never a float like 1.84e19. Foundation's
        // JSONDecoder uses an integer scanner (no Double round-trip), so UInt64.max survives
        // exactly; this assertion fails loudly if a future path ever coerces through Double.
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("18446744073709551615"))
    }

    @Test("ScanState round-trips, preserving the U+0001 dedup keys and file identity")
    func scanStateRoundTrip() throws {
        let e1 = event("msg_1")
        let e2 = event("msg_2", input: 99)
        let key1 = "\(ProviderID.claude.rawValue)\u{1}\(e1.id)"
        let key2 = "\(ProviderID.claude.rawValue)\u{1}\(e2.id)"
        let state = ScanState(
            files: ["/a/b.jsonl": FileScanState(size: 100, modified: 12.5, offset: 80, inode: 4242, createdAt: 9.0)],
            events: [key1: e1, key2: e2]
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ScanState.self, from: data)
        #expect(decoded == state)
        #expect(decoded.events[key1] == e1) // the U+0001-containing key survived as a JSON object key
        #expect(decoded.files["/a/b.jsonl"]?.inode == 4242)
        #expect(decoded.files["/a/b.jsonl"]?.createdAt == 9.0)
    }
}
