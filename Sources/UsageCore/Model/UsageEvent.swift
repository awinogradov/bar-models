import Foundation

/// Identifies a usage provider (the CLI/agent the data came from).
///
/// A struct (not an enum) so new providers can be added without editing a
/// central enum, while still being a `String`-backed `RawRepresentable` for
/// `@AppStorage` binding.
public struct ProviderID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let claude = ProviderID(rawValue: "claude")
    public static let codex  = ProviderID(rawValue: "codex")
    public static let gemini = ProviderID(rawValue: "gemini")

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One normalized, deduplicated assistant turn — the common currency every
/// provider parses into. The aggregation, pricing, limit, and rendering layers
/// only ever see `UsageEvent`, never provider-specific shapes.
public struct UsageEvent: Sendable, Identifiable, Equatable {
    /// The provider's message id — the dedup key. Streaming repeats the same id
    /// with identical token tuples, so last-wins dedup is correct.
    public let id: String
    public let provider: ProviderID
    public let timestamp: Date
    public let model: String
    public let tokens: TokenCounts

    public init(id: String, provider: ProviderID, timestamp: Date, model: String, tokens: TokenCounts) {
        self.id = id
        self.provider = provider
        self.timestamp = timestamp
        self.model = model
        self.tokens = tokens
    }
}
