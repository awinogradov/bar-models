import Testing
import Foundation
@testable import UsageCore

@Suite("StatusLineConfig")
struct StatusLineConfigTests {
    private let script = "/Users/me/.claude/bar-models/bar-models-statusline.sh"

    private func root(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func command(_ data: Data) throws -> String? {
        (try root(data)["statusLine"] as? [String: Any])?["command"] as? String
    }

    @Test("creates a statusLine when settings are absent or empty")
    func createsWhenAbsent() throws {
        for input: Data? in [nil, Data()] {
            let result = try StatusLineConfig.enable(settings: input, scriptCommand: script)
            #expect(try command(result.settings) == script)
            #expect(result.priorCommand == nil)
            #expect(result.priorStatusLine == nil)
        }
    }

    @Test("wraps an existing command (with args, quotes, a pipe) and preserves siblings")
    func wrapsExisting() throws {
        let prior = "starship | tee /tmp/x --flag 'a b'"
        let settings = Data(#"{"model": "opus", "statusLine": {"type": "command", "command": "\#(prior)", "padding": 2}, "permissions": {"allow": ["Bash"]}}"#.utf8)
        let result = try StatusLineConfig.enable(settings: settings, scriptCommand: script)

        #expect(try command(result.settings) == script)
        #expect(result.priorCommand == prior)
        #expect(result.priorStatusLine != nil)
        // siblings untouched
        #expect(try root(result.settings)["model"] as? String == "opus")
        #expect(try root(result.settings)["permissions"] != nil)
    }

    @Test("is idempotent when our hook is already installed")
    func idempotent() throws {
        let settings = Data(#"{"statusLine": {"type": "command", "command": "\#(script)"}}"#.utf8)
        let result = try StatusLineConfig.enable(settings: settings, scriptCommand: script)
        #expect(try command(result.settings) == script)
        #expect(result.priorCommand == nil)
        #expect(result.priorStatusLine == nil)
    }

    @Test("disable restores the exact prior command (round-trips args and quotes)")
    func disableRestores() throws {
        let prior = "starship | tee /tmp/x --flag 'a b'"
        let settings = Data(#"{"statusLine": {"type": "command", "command": "\#(prior)", "padding": 2}}"#.utf8)
        let enabled = try StatusLineConfig.enable(settings: settings, scriptCommand: script)
        let restored = try StatusLineConfig.disable(settings: enabled.settings, priorStatusLine: enabled.priorStatusLine)

        #expect(try command(restored) == prior)
        #expect((try root(restored)["statusLine"] as? [String: Any])?["padding"] as? Int == 2)
    }

    @Test("disable removes statusLine when there was no prior")
    func disableRemovesWhenNoPrior() throws {
        let enabled = try StatusLineConfig.enable(settings: Data(#"{"model": "opus"}"#.utf8), scriptCommand: script)
        let disabled = try StatusLineConfig.disable(settings: enabled.settings, priorStatusLine: enabled.priorStatusLine)
        #expect(try root(disabled)["statusLine"] == nil)
        #expect(try root(disabled)["model"] as? String == "opus") // sibling survives
    }

    @Test("unparseable settings throw rather than being overwritten")
    func unparseableThrows() {
        #expect(throws: StatusLineConfig.ConfigError.self) {
            try StatusLineConfig.enable(settings: Data("{ not json,".utf8), scriptCommand: script)
        }
    }
}
