import Testing
import Foundation
@testable import UsageCore

@Suite("ClaudeProvider.parse")
struct ClaudeParseTests {
    private let provider = ClaudeProvider()
    private func parse(_ json: String) -> UsageEvent? { provider.parse(line: Data(json.utf8)) }

    @Test("parses a normal assistant turn")
    func assistantTurn() {
        let e = parse(#"""
        {"type":"assistant","timestamp":"2026-05-22T08:15:22.881Z","message":{"id":"m1","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":5,"cache_read_input_tokens":100}}}
        """#)
        #expect(e?.id == "m1")
        #expect(e?.provider == .claude)
        #expect(e?.model == "claude-opus-4-8")
        #expect(e?.tokens == TokenCounts(input: 10, output: 20, cacheWrite: 5, cacheRead: 100))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let expected = utc.date(from: DateComponents(year: 2026, month: 5, day: 22, hour: 8, minute: 15, second: 22))
        #expect(e?.timestamp == expected)
    }

    @Test("ignores usage.iterations (no double count)")
    func iterationsIgnored() {
        let e = parse(#"""
        {"type":"assistant","timestamp":"2026-05-22T08:15:22Z","message":{"id":"m2","model":"x","usage":{"input_tokens":3,"output_tokens":4,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"iterations":[{"input_tokens":3,"output_tokens":4},{"input_tokens":3,"output_tokens":4}]}}}
        """#)
        #expect(e?.tokens.inputOutput == 7) // not 21
    }

    @Test("drops all-zero-token records")
    func zeroDropped() {
        let e = parse(#"{"type":"assistant","timestamp":"2026-05-22T08:15:22Z","message":{"id":"z","model":"x","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#)
        #expect(e == nil)
    }

    @Test("drops non-assistant records")
    func wrongType() {
        let e = parse(#"{"type":"user","timestamp":"2026-05-22T08:15:22Z","message":{"id":"u","usage":{"input_tokens":5}}}"#)
        #expect(e == nil)
    }

    @Test("drops records without a message id")
    func missingID() {
        let e = parse(#"{"type":"assistant","timestamp":"2026-05-22T08:15:22Z","message":{"model":"x","usage":{"input_tokens":5}}}"#)
        #expect(e == nil)
    }

    @Test("drops corrupt / non-JSON lines")
    func corrupt() {
        #expect(parse("not json at all") == nil)
        #expect(parse(#"{"type":"assistant","message":{"id":"x","usage":{"#) == nil) // truncated
        #expect(parse("") == nil)
    }

    @Test("missing token fields default to zero")
    func partialUsage() {
        let e = parse(#"{"type":"assistant","timestamp":"2026-05-22T08:15:22Z","message":{"id":"p","model":"claude-haiku-4-5","usage":{"output_tokens":9}}}"#)
        #expect(e?.tokens == TokenCounts(input: 0, output: 9, cacheWrite: 0, cacheRead: 0))
    }

    @Test("unknown/synthetic model is kept as an event (cost flags it later)")
    func syntheticModel() {
        let e = parse(#"{"type":"assistant","timestamp":"2026-05-22T08:15:22Z","message":{"id":"s","model":"<synthetic>","usage":{"input_tokens":1,"output_tokens":1}}}"#)
        #expect(e?.model == "<synthetic>")
    }
}
