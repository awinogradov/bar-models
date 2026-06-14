import Foundation

/// USD price per **million** tokens for one model.
public struct ModelRate: Sendable, Equatable {
    public let input: Double
    public let output: Double
    public let cacheWrite5m: Double
    public let cacheRead: Double

    public init(input: Double, output: Double, cacheWrite5m: Double, cacheRead: Double) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheRead = cacheRead
    }
}

/// Per-model price table with a three-tier match: exact model id → longest
/// id prefix → family keyword (`fable`/`opus`/`sonnet`/`haiku`). Unknown models
/// return `nil` (the caller flags them and excludes them from cost).
public struct PricingTable: Sendable {
    private struct Keyword: Sendable { let keyword: String; let rate: ModelRate }

    private let exact: [String: ModelRate]
    private let keywords: [Keyword]

    public init(exact: [String: ModelRate], keywords: [(String, ModelRate)]) {
        self.exact = exact
        self.keywords = keywords.map { Keyword(keyword: $0.0, rate: $0.1) }
    }

    /// Resolve a model id to a rate, or `nil` if unrecognized.
    public func rate(for model: String) -> ModelRate? {
        let m = model.lowercased()
        if let r = exact[m] { return r }
        // Longest-prefix match (so "claude-opus-4-8-<suffix>" maps to opus-4-8).
        for key in exact.keys.sorted(by: { $0.count > $1.count }) where m.hasPrefix(key) {
            return exact[key]
        }
        for kw in keywords where m.contains(kw.keyword) { return kw.rate }
        return nil
    }

    /// Estimated USD cost for a token bundle on a given model. `nil` ⇒ unknown model.
    public func cost(_ tokens: TokenCounts, model: String) -> Double? {
        guard let r = rate(for: model) else { return nil }
        let perMillion = 1_000_000.0
        return Double(tokens.input)      / perMillion * r.input
             + Double(tokens.output)     / perMillion * r.output
             + Double(tokens.cacheWrite) / perMillion * r.cacheWrite5m
             + Double(tokens.cacheRead)  / perMillion * r.cacheRead
    }
}

public extension PricingTable {
    /// Anthropic API pricing (per million tokens), authoritative as of 2026-06.
    /// cache-write 5m = 1.25× input, cache-read = 0.1× input.
    static let claude = PricingTable(
        exact: [
            "claude-fable-5":            ModelRate(input: 10, output: 50, cacheWrite5m: 12.50, cacheRead: 1.00),
            "claude-opus-4-8":           ModelRate(input: 5,  output: 25, cacheWrite5m: 6.25,  cacheRead: 0.50),
            "claude-opus-4-7":           ModelRate(input: 5,  output: 25, cacheWrite5m: 6.25,  cacheRead: 0.50),
            "claude-sonnet-4-6":         ModelRate(input: 3,  output: 15, cacheWrite5m: 3.75,  cacheRead: 0.30),
            "claude-haiku-4-5":          ModelRate(input: 1,  output: 5,  cacheWrite5m: 1.25,  cacheRead: 0.10),
            "claude-haiku-4-5-20251001": ModelRate(input: 1,  output: 5,  cacheWrite5m: 1.25,  cacheRead: 0.10),
        ],
        keywords: [
            ("fable",  ModelRate(input: 10, output: 50, cacheWrite5m: 12.50, cacheRead: 1.00)),
            ("opus",   ModelRate(input: 5,  output: 25, cacheWrite5m: 6.25,  cacheRead: 0.50)),
            ("sonnet", ModelRate(input: 3,  output: 15, cacheWrite5m: 3.75,  cacheRead: 0.30)),
            ("haiku",  ModelRate(input: 1,  output: 5,  cacheWrite5m: 1.25,  cacheRead: 0.10)),
        ]
    )
}
