import Foundation

/// Lenient `Decodable` mirror of one Claude Code transcript line.
///
/// Every field is optional so malformed/partial lines never throw fatally
/// (`parse` turns a decode failure into `nil`). We deliberately decode **only**
/// the four top-level `usage` fields — `usage.iterations[]` is intentionally not
/// modeled, because it repeats the same counts and would double-count.
struct ClaudeRecord: Decodable {
    let type: String?
    let timestamp: String?
    let message: Message?

    struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let inputTokens: UInt64?
        let outputTokens: UInt64?
        let cacheCreationInputTokens: UInt64?
        let cacheReadInputTokens: UInt64?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}

/// Fast, allocation-light, thread-safe ISO-8601-UTC parser for the fixed
/// `YYYY-MM-DDTHH:MM:SS[.fff]Z` shape Claude Code writes. Sub-second precision is
/// ignored (irrelevant for day bucketing and 5-hour windows). Avoids
/// `ISO8601DateFormatter` (slower, finicky about the fractional-seconds option)
/// and non-`Sendable` shared `DateFormatter`s.
enum ClaudeTimestamp {
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func parse(_ string: String) -> Date? {
        let b = Array(string.utf8)
        guard b.count >= 19 else { return nil } // "YYYY-MM-DDTHH:MM:SS"

        func int(_ lo: Int, _ hi: Int) -> Int? {
            var v = 0
            for i in lo..<hi {
                let c = b[i]
                guard c >= 48, c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        // Separators: '-' '-' 'T'|' ' ':' ':'
        guard b[4] == 0x2D, b[7] == 0x2D, b[10] == 0x54 || b[10] == 0x20,
              b[13] == 0x3A, b[16] == 0x3A else { return nil }
        guard let year = int(0, 4), let month = int(5, 7), let day = int(8, 10),
              let hour = int(11, 13), let minute = int(14, 16), let second = int(17, 19)
        else { return nil }

        return utc.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        ))
    }
}
