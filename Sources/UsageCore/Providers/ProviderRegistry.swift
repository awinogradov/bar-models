import Foundation

/// The set of providers the app scans. The MVP ships only `ClaudeProvider`;
/// adding Codex/Gemini means appending them here (plus their own folder).
public struct ProviderRegistry: Sendable {
    public let providers: [any UsageProvider]

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    /// The default registry — Claude only, for now.
    public static let `default` = ProviderRegistry(providers: [ClaudeProvider()])

    public func provider(_ id: ProviderID) -> (any UsageProvider)? {
        providers.first { $0.id == id }
    }
}
