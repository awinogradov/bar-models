import Foundation

/// Which definition of "tokens" a displayed value uses.
///
/// Cache-reads dominate raw totals (~97% in real data), so a naive total is
/// almost all cache traffic and barely moves with real work. `inputOutputOnly`
/// is the most intuitive headline; `billableTotal` correlates with cost and is
/// what the plan-limit math uses.
public enum TokenDefinition: String, Sendable, Codable, CaseIterable {
    case inputOutputOnly
    case withCacheWrite
    case billableTotal
}

/// The four token buckets Claude (and most providers) report per turn.
public struct TokenCounts: Sendable, Equatable, Codable {
    public var input: UInt64
    public var output: UInt64
    /// `cache_creation_input_tokens` — tokens written to the prompt cache (~1.25x input).
    public var cacheWrite: UInt64
    /// `cache_read_input_tokens` — tokens served from the prompt cache (~0.1x input).
    public var cacheRead: UInt64

    public init(input: UInt64 = 0, output: UInt64 = 0, cacheWrite: UInt64 = 0, cacheRead: UInt64 = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public static let zero = TokenCounts()

    public var isZero: Bool { input == 0 && output == 0 && cacheWrite == 0 && cacheRead == 0 }

    public var inputOutput: UInt64 { input &+ output }
    public var billableTotal: UInt64 { input &+ output &+ cacheWrite &+ cacheRead }

    /// The scalar value for a given display definition.
    public func value(for definition: TokenDefinition) -> UInt64 {
        switch definition {
        case .inputOutputOnly: return inputOutput
        case .withCacheWrite:  return input &+ output &+ cacheWrite
        case .billableTotal:   return billableTotal
        }
    }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input &+ rhs.input,
            output: lhs.output &+ rhs.output,
            cacheWrite: lhs.cacheWrite &+ rhs.cacheWrite,
            cacheRead: lhs.cacheRead &+ rhs.cacheRead
        )
    }

    public static func += (lhs: inout TokenCounts, rhs: TokenCounts) {
        lhs = lhs + rhs
    }
}
