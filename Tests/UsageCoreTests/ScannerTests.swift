import Testing
import Foundation
@testable import UsageCore

@Suite("UsageScanner")
struct ScannerTests {
    private func line(_ id: String, input: Int) -> String {
        #"{"type":"assistant","timestamp":"2026-05-22T08:00:00Z","message":{"id":"\#(id)","model":"claude-opus-4-8","usage":{"input_tokens":\#(input),"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
    }

    @Test("dedups by message id within and across files")
    func dedup() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "scan-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Within a file, streaming repeats the same id; the later line wins (deterministic
        // by line order). Across files a duplicate id carries identical tokens, so file
        // enumeration order doesn't matter — both resolve m1 to input 9.
        try (line("m1", input: 1) + "\n" + line("m1", input: 9) + "\n" + line("m2", input: 2) + "\n")
            .write(to: root.appending(path: "a.jsonl"), atomically: true, encoding: .utf8)
        try (line("m1", input: 9) + "\n" + #"{"type":"user","message":{"id":"u"}}"# + "\n")
            .write(to: root.appending(path: "b.jsonl"), atomically: true, encoding: .utf8)

        let events = UsageScanner().events(in: [root], provider: ClaudeProvider())
        #expect(events.count == 2) // m1, m2 (within-file dup collapsed; user line ignored)
        #expect(events.first { $0.id == "m1" }?.tokens.input == 9)
    }

    @Test("missing root yields no events")
    func missingRoot() {
        let events = UsageScanner().events(
            in: [URL(filePath: "/no/such/dir-\(UUID().uuidString)")],
            provider: ClaudeProvider()
        )
        #expect(events.isEmpty)
    }
}
