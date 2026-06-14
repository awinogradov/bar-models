import Foundation

/// Coarse "is there anything to show?" state derived from a scan result. Lets the
/// menu-bar UI drive its loading / first-run / empty / ready experience without
/// reasoning about `nil` snapshots and zero counts itself. Provider-neutral and
/// pure, so it's unit-testable away from the app target.
public enum DataAvailability: Sendable, Equatable {
    /// The first scan hasn't completed yet.
    case loading
    /// No provider data directory exists (e.g. `~/.claude` not found) — a machine
    /// that has never run a supported assistant.
    case noSource
    /// Data directories exist but hold no usage records yet.
    case empty
    /// Usage records are present.
    case ready

    /// - Parameters:
    ///   - snapshot: the latest snapshot, or `nil` before the first scan finishes.
    ///   - hasDataSources: whether any provider data root existed during the scan.
    public init(snapshot: UsageSnapshot?, hasDataSources: Bool) {
        guard let snapshot else { self = .loading; return }
        if snapshot.eventCount > 0 {
            self = .ready
        } else if hasDataSources {
            self = .empty
        } else {
            self = .noSource
        }
    }
}
