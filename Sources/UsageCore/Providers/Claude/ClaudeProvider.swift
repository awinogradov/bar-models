import Foundation

/// Usage provider for Claude Code.
///
/// Data lives in `~/.claude/projects/**/*.jsonl` (one JSON object per line).
/// Full line parsing (dedup by `message.id`, skip-zero, ignore `usage.iterations`)
/// lands in M1; this M0 stub wires up the roots and pricing so the engine builds.
public struct ClaudeProvider: UsageProvider {
    public init() {}

    public let id = ProviderID.claude
    public let displayName = "Claude Code"

    public func dataRoots() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".claude/projects"),
            // Optional Xcode CodingAssistant transcripts (toggled on in M3):
            // home.appending(path: "Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects"),
        ]
        return candidates.filter { fm.fileExists(atPath: $0.path) }
    }

    public func parse(line: Data) -> UsageEvent? {
        guard !line.isEmpty,
              let record = try? JSONDecoder().decode(ClaudeRecord.self, from: line),
              record.type == "assistant",
              let message = record.message,
              let id = message.id, !id.isEmpty,
              let usage = message.usage,
              let timestampString = record.timestamp,
              let timestamp = ClaudeTimestamp.parse(timestampString)
        else { return nil }

        let tokens = TokenCounts(
            input: usage.inputTokens ?? 0,
            output: usage.outputTokens ?? 0,
            cacheWrite: usage.cacheCreationInputTokens ?? 0,
            cacheRead: usage.cacheReadInputTokens ?? 0
        )
        guard !tokens.isZero else { return nil }

        return UsageEvent(
            id: id,
            provider: self.id,
            timestamp: timestamp,
            model: message.model ?? "unknown",
            tokens: tokens
        )
    }

    public var pricing: PricingTable { .claude }
}
