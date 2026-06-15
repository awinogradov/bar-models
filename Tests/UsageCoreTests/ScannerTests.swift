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

    @Test("incremental scan reads only appended lines and advances the offset")
    func incremental() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "inc-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appending(path: "s.jsonl")
        let scanner = UsageScanner()

        try Data((line("m1", input: 1) + "\n").utf8).write(to: file)
        var state = scanner.updateState(ScanState(), roots: [root], provider: ClaudeProvider())
        #expect(state.events.count == 1)
        let firstOffset = state.files.values.first?.offset ?? 0
        #expect(firstOffset > 0)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line("m2", input: 2) + "\n").utf8))
        try handle.close()

        state = scanner.updateState(state, roots: [root], provider: ClaudeProvider())
        #expect(state.events.count == 2) // m1 retained, m2 appended
        #expect((state.files.values.first?.offset ?? 0) > firstOffset)

        // No change → no growth, still 2 events.
        state = scanner.updateState(state, roots: [root], provider: ClaudeProvider())
        #expect(state.events.count == 2)
    }

    @Test("a replaced file (new inode/birthtime) re-reads from offset 0")
    func rotation() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "rot-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appending(path: "s.jsonl")
        let scanner = UsageScanner()

        try Data((line("m1", input: 1) + "\n").utf8).write(to: file)
        var state = scanner.updateState(ScanState(), roots: [root], provider: ClaudeProvider())
        #expect(state.events.count == 1)

        // Replace atomically (temp + rename ⇒ new inode + new birthtime) with two
        // records of the same line length. A stale-offset resume would seek past
        // "mA" and miss it; correct rotation detection re-reads from 0 and sees both.
        try (line("mA", input: 2) + "\n" + line("mB", input: 3) + "\n")
            .write(to: file, atomically: true, encoding: .utf8)
        state = scanner.updateState(state, roots: [root], provider: ClaudeProvider())
        #expect(state.events["claude\u{1}mA"] != nil) // proves the read restarted at 0
        #expect(state.events["claude\u{1}mB"] != nil)
    }

    @Test("a shrunk file re-reads from offset 0")
    func shrink() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "shrink-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appending(path: "s.jsonl")
        let scanner = UsageScanner()

        try (line("m1", input: 1) + "\n" + line("m2", input: 2) + "\n")
            .write(to: file, atomically: false, encoding: .utf8)
        var state = scanner.updateState(ScanState(), roots: [root], provider: ClaudeProvider())
        #expect(state.events.count == 2)

        // Truncate in place (same inode) to a single, smaller, different record.
        try (line("m3", input: 3) + "\n").write(to: file, atomically: false, encoding: .utf8)
        state = scanner.updateState(state, roots: [root], provider: ClaudeProvider())
        #expect(state.events["claude\u{1}m3"] != nil) // size < saved ⇒ re-read from 0 found it
    }
}
