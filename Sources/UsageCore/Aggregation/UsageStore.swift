import Foundation
import Observation

/// The `@MainActor @Observable` hub the SwiftUI views bind to. Scanning and
/// aggregation run off-main in a detached task; the resulting `Sendable`
/// snapshot is published on the main actor. Refreshes are single-flighted.
@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var isScanning = false
    /// Whether any provider data root existed at the last scan — distinguishes a
    /// never-used machine (no `~/.claude`) from one with an empty data folder.
    public private(set) var hasDataSources = false
    public var zone: PeriodBucketer.Zone = .local

    private let scanner: UsageScanner
    private var scanState = ScanState()

    public init(scanner: UsageScanner = UsageScanner()) {
        self.scanner = scanner
    }

    public func refresh() async {
        guard !isScanning else { return } // single-flight (MainActor serializes the check+set)
        isScanning = true
        defer { isScanning = false }

        let scanner = self.scanner
        let zone = self.zone
        let state = self.scanState
        let result = await Task.detached(priority: .utility) { () -> (ScanState, UsageSnapshot, Bool) in
            let updated = scanner.update(state) // first pass full; later passes read only appended bytes
            let pricing = scanner.registry.providers.first?.pricing ?? .claude
            let snapshot = Aggregator().aggregate(updated.allEvents, using: PeriodBucketer(zone: zone, now: Date()), pricing: pricing)
            let hasSources = scanner.registry.providers.contains { !$0.dataRoots().isEmpty }
            return (updated, snapshot, hasSources)
        }.value
        self.scanState = result.0
        self.snapshot = result.1
        self.hasDataSources = result.2
    }
}
