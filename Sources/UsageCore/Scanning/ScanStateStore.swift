import Foundation

/// Persists the accumulated ``ScanState`` (per-file cursors + the deduped event
/// map) between launches, so the first scan after startup resumes from saved
/// byte offsets instead of cold-scanning the whole `~/.claude` tree.
///
/// The cache is a pure optimization: a corrupt, version-mismatched, or stale
/// file is silently discarded and the app falls back to a full scan, exactly as
/// before persistence existed. Modeled on ``LimitSource`` — an injectable `url`
/// and lenient `try?` reads — and writes atomically (temp + rename).
public struct ScanStateStore: Sendable {
    public let url: URL
    /// A cache older than this is discarded on load, bounding worst-case
    /// divergence if a saved offset ever goes stale; a full rescan is only a few
    /// seconds. Generous by default so normal use always hits the cache.
    public let maxAge: TimeInterval

    /// `~/Library/Caches/bar-models/scan-state.json` — a fixed `bar-models`
    /// subfolder (mirroring ``LimitSource``'s `~/.claude/bar-models/`) because
    /// `Bundle.main.bundleIdentifier` is nil under `swift run`. Caches is the
    /// right domain: the file is fully regenerable, so an OS purge degrades to a
    /// full scan rather than data loss.
    public static var defaultURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        return caches.appendingPathComponent("bar-models/scan-state.json")
    }

    public init(url: URL = ScanStateStore.defaultURL, maxAge: TimeInterval = 14 * 24 * 60 * 60) {
        self.url = url
        self.maxAge = maxAge
    }

    /// The persisted state as of `now`, or `nil` when the cache is missing,
    /// unreadable, corrupt, a different schema version, or older than `maxAge`.
    /// Cursors whose backing file no longer exists are pruned — the event map is
    /// keyed by `(provider, id)`, so a re-appearing path re-reads idempotently —
    /// while the size/mtime resume decision is left to `UsageScanner.updateState`
    /// (its single home, never duplicated here).
    public func load(now: Date) -> ScanState? {
        guard let data = try? Data(contentsOf: url),
              let persisted = try? Self.makeDecoder().decode(PersistedScanState.self, from: data),
              persisted.version == PersistedScanState.currentVersion,
              now.timeIntervalSince1970 - persisted.savedAt <= maxAge
        else { return nil }

        var state = persisted.state
        let fm = FileManager.default
        state.files = state.files.filter { fm.fileExists(atPath: $0.key) }
        return state
    }

    /// Atomically write `state` stamped with `now`. Best-effort: any failure
    /// (e.g. a full disk) is swallowed — the next launch simply cold-scans.
    public func save(_ state: ScanState, now: Date) {
        let payload = PersistedScanState(
            version: PersistedScanState.currentVersion,
            savedAt: now.timeIntervalSince1970,
            state: state
        )
        guard let data = try? Self.makeEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Schema

    /// Versioned envelope around ``ScanState``. Wrapping (rather than embedding
    /// the version inside `ScanState`) keeps the version readable independent of
    /// the payload, and stamps `savedAt` for the staleness check.
    private struct PersistedScanState: Codable {
        static let currentVersion = 1
        var version: Int
        var savedAt: TimeInterval
        var state: ScanState
    }

    // MARK: Coders

    // Fresh instances per call (a `static let` of a non-Sendable `JSONEncoder`
    // would trip Swift 6 strict concurrency). The pinned strategies codify the
    // on-disk format so a later "tidy-up" cannot silently break it: snake_case
    // keys would mangle the U+0001 dedup keys, and `.sortedKeys` would churn the
    // file for no benefit.
    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .deferredToDate
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }
}
