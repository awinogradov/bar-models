import Foundation

/// Walks each provider's data roots, parses every `*.jsonl` line, and dedups
/// globally by `(provider, message.id)` (last-wins). M1 does a full cold scan;
/// incremental rescanning (byte-offset resume via `FileScanState`) arrives in M4.
public struct UsageScanner: Sendable {
    public let registry: ProviderRegistry

    public init(registry: ProviderRegistry = .default) {
        self.registry = registry
    }

    /// Full scan across every provider in the registry.
    public func scan() -> [UsageEvent] {
        var byKey: [String: UsageEvent] = [:]
        for provider in registry.providers {
            collect(into: &byKey, roots: provider.dataRoots(), provider: provider)
        }
        return Array(byKey.values)
    }

    /// Scan explicit roots with a specific provider (used by tests and callers
    /// that already resolved roots).
    public func events(in roots: [URL], provider: any UsageProvider) -> [UsageEvent] {
        var byKey: [String: UsageEvent] = [:]
        collect(into: &byKey, roots: roots, provider: provider)
        return Array(byKey.values)
    }

    private func collect(into byKey: inout [String: UsageEvent], roots: [URL], provider: any UsageProvider) {
        for root in roots {
            for file in Self.jsonlFiles(under: root) {
                _ = try? JSONLReader.readLines(from: file) { line in
                    if let event = provider.parse(line: line) {
                        byKey["\(event.provider.rawValue)\u{1}\(event.id)"] = event
                    }
                }
            }
        }
    }

    /// All `*.jsonl` files under `root`, recursively. Missing root ⇒ empty.
    static func jsonlFiles(under root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            files.append(url)
        }
        return files
    }
}
