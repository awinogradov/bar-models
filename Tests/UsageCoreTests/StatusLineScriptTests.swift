import Testing
import Foundation
@testable import UsageCore

/// Drives `scripts/bar-models-statusline.sh` as a subprocess with a throwaway
/// `HOME`, asserting the snapshot it writes and its pass-through behaviour. The
/// snapshot-content cases require `jq` (the script's dependency) and are skipped
/// when it is absent; the pass-through cases need no `jq`.
@Suite("status-line script")
struct StatusLineScriptTests {
    static let jqAvailable: Bool = ["/opt/homebrew/bin/jq", "/usr/local/bin/jq", "/usr/bin/jq", "/bin/jq"]
        .contains { FileManager.default.isExecutableFile(atPath: $0) }

    private var scriptURL: URL {
        URL(fileURLWithPath: #filePath)        // …/Tests/UsageCoreTests/StatusLineScriptTests.swift
            .deletingLastPathComponent()       // …/Tests/UsageCoreTests
            .deletingLastPathComponent()       // …/Tests
            .deletingLastPathComponent()       // repo root
            .appendingPathComponent("scripts/bar-models-statusline.sh")
    }

    private func tempHome() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slhome-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func run(input: String, home: URL, path: String? = nil) throws -> (stdout: String, code: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home.path
        if let path { env["PATH"] = path }
        process.environment = env

        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        try process.run()
        stdinPipe.fileHandleForWriting.write(Data(input.utf8))
        stdinPipe.fileHandleForWriting.closeFile()
        let out = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: out, as: UTF8.self), process.terminationStatus)
    }

    private func snapshot(in home: URL) throws -> OfficialSnapshot {
        let url = home.appendingPathComponent(".claude/bar-models/snapshot.json")
        return try JSONDecoder().decode(OfficialSnapshot.self, from: Data(contentsOf: url))
    }

    private let fullInput = #"""
    {"model": {"display_name": "Opus"},
     "rate_limits": {
       "five_hour": {"used_percentage": 42.5, "resets_at": 1738425600},
       "seven_day": {"used_percentage": 31, "resets_at": 1738857600}}}
    """#

    @Test("captures official fields into the snapshot", .enabled(if: jqAvailable))
    func capturesOfficial() throws {
        let home = try tempHome()
        let result = try run(input: fullInput, home: home)
        #expect(result.code == 0)
        let snap = try snapshot(in: home)
        #expect(snap.fiveHour == 42.5)
        #expect(snap.sevenDay == 31)
        #expect(snap.fiveHourResetsAt == 1738425600)
        #expect(snap.model == "Opus")
        #expect(snap.ts > 0)
    }

    @Test("finds jq even with a minimal PATH", .enabled(if: jqAvailable))
    func minimalPath() throws {
        let home = try tempHome()
        let result = try run(input: fullInput, home: home, path: "/usr/bin:/bin")
        #expect(result.code == 0)
        #expect(try snapshot(in: home).fiveHour == 42.5) // script's own PATH-prepend located jq
    }

    @Test("absent rate_limits yields a snapshot with no percentages", .enabled(if: jqAvailable))
    func absentRateLimits() throws {
        let home = try tempHome()
        let result = try run(input: #"{"model": {"display_name": "Opus"}}"#, home: home)
        #expect(result.code == 0)
        let snap = try snapshot(in: home)
        #expect(snap.fiveHour == nil)
        #expect(snap.sevenDay == nil)
        #expect(snap.ts > 0)
    }

    @Test("passes stdin through a wrapped command, preserving output")
    func passThrough() throws {
        let home = try tempHome()
        let dir = home.appendingPathComponent(".claude/bar-models", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // a wrapped command with a pipe + quotes exercises round-trip fidelity
        try "cat | sed 's/foo/bar/'".write(to: dir.appendingPathComponent("wrapped-command"),
                                           atomically: true, encoding: .utf8)
        let result = try run(input: "foo", home: home)
        #expect(result.code == 0)
        #expect(result.stdout.contains("bar"))
    }

    @Test("prints nothing when there is no wrapped command")
    func noWrappedCommand() throws {
        let home = try tempHome()
        let result = try run(input: #"{"model": {"display_name": "Opus"}}"#, home: home)
        #expect(result.code == 0)
        #expect(result.stdout.isEmpty)
    }

    @Test("a failing wrapped command propagates a non-zero exit")
    func failingWrappedCommand() throws {
        let home = try tempHome()
        let dir = home.appendingPathComponent(".claude/bar-models", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "exit 3".write(to: dir.appendingPathComponent("wrapped-command"),
                           atomically: true, encoding: .utf8)
        let result = try run(input: "anything", home: home)
        #expect(result.code != 0)
    }
}
