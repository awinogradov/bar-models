import Testing
import Foundation
@testable import UsageCore

@Suite("TokenCounts")
struct TokenCountsTests {
    @Test("addition sums each bucket")
    func addition() {
        let a = TokenCounts(input: 10, output: 20, cacheWrite: 30, cacheRead: 40)
        let b = TokenCounts(input: 1, output: 2, cacheWrite: 3, cacheRead: 4)
        #expect(a + b == TokenCounts(input: 11, output: 22, cacheWrite: 33, cacheRead: 44))
    }

    @Test("definitions select the right buckets")
    func definitions() {
        let t = TokenCounts(input: 100, output: 200, cacheWrite: 1_000, cacheRead: 10_000)
        #expect(t.value(for: .inputOutputOnly) == 300)
        #expect(t.value(for: .withCacheWrite) == 1_300)
        #expect(t.value(for: .billableTotal) == 11_300)
    }

    @Test("zero is detected")
    func zero() {
        #expect(TokenCounts.zero.isZero)
        #expect(!TokenCounts(input: 1).isZero)
    }
}

@Suite("PricingTable")
struct PricingTableTests {
    @Test("exact model id matches")
    func exact() {
        let r = PricingTable.claude.rate(for: "claude-opus-4-8")
        #expect(r?.input == 5)
        #expect(r?.output == 25)
    }

    @Test("date-suffixed id falls back to prefix match")
    func prefix() {
        #expect(PricingTable.claude.rate(for: "claude-sonnet-4-6-20260101")?.input == 3)
    }

    @Test("family keyword catches unknown versions")
    func keyword() {
        #expect(PricingTable.claude.rate(for: "claude-opus-9-9")?.output == 25)
    }

    @Test("unknown model returns nil")
    func unknown() {
        #expect(PricingTable.claude.rate(for: "<synthetic>") == nil)
    }

    @Test("cost is computed per million tokens")
    func cost() {
        // 1M output on opus-4-8 = $25
        let c = PricingTable.claude.cost(TokenCounts(output: 1_000_000), model: "claude-opus-4-8")
        #expect(c == 25.0)
    }
}

@Suite("ClaudeProvider")
struct ClaudeProviderTests {
    @Test("identity and pricing wired up")
    func identity() {
        let p = ClaudeProvider()
        #expect(p.id == .claude)
        #expect(p.displayName == "Claude Code")
        #expect(p.pricing.rate(for: "claude-haiku-4-5")?.input == 1)
    }
}
