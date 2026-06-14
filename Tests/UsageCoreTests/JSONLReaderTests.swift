import Testing
import Foundation
@testable import UsageCore

@Suite("JSONLReader")
struct JSONLReaderTests {
    private func withTempFile(_ contents: String, _ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "jsonl-\(UUID().uuidString).jsonl")
        try Data(contents.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    @Test("yields complete lines and stops before a trailing partial")
    func partial() throws {
        try withTempFile("line1\nline2\npartial") { url in
            var lines: [String] = []
            let offset = try JSONLReader.readLines(from: url) {
                lines.append(String(decoding: $0, as: UTF8.self))
            }
            #expect(lines == ["line1", "line2"])
            // "line1\n" (6) + "line2\n" (6) = 12; "partial" is unconsumed.
            #expect(offset == 12)
        }
    }

    @Test("resumes from a byte offset")
    func resume() throws {
        try withTempFile("aaa\nbbb\nccc\n") { url in
            var lines: [String] = []
            let offset = try JSONLReader.readLines(from: url, startingAt: 4) {
                lines.append(String(decoding: $0, as: UTF8.self))
            }
            #expect(lines == ["bbb", "ccc"])
            #expect(offset == 12)
        }
    }

    @Test("handles a final newline (no partial)")
    func trailingNewline() throws {
        try withTempFile("only\n") { url in
            var lines: [String] = []
            let offset = try JSONLReader.readLines(from: url) {
                lines.append(String(decoding: $0, as: UTF8.self))
            }
            #expect(lines == ["only"])
            #expect(offset == 5)
        }
    }

    @Test("small chunk size still reconstructs lines")
    func smallChunks() throws {
        try withTempFile("hello\nworld\n") { url in
            var lines: [String] = []
            try JSONLReader.readLines(from: url, chunkSize: 3) {
                lines.append(String(decoding: $0, as: UTF8.self))
            }
            #expect(lines == ["hello", "world"])
        }
    }
}
