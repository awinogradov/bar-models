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
    private let limitSource: LimitSource
    private let scanStateStore: ScanStateStore?
    private var scanState = ScanState()
    /// The persisted cache is loaded once, off-main, on the first refresh — never
    /// in `init`, where decoding the event map on the main actor would defeat the
    /// instant-startup goal this persistence exists for.
    private var didLoadPersisted = false
    private var saveTask: Task<Void, Never>?

    public init(scanner: UsageScanner = UsageScanner(),
                limitSource: LimitSource = LimitSource(),
                scanStateStore: ScanStateStore? = ScanStateStore()) {
        self.scanner = scanner
        self.limitSource = limitSource
        self.scanStateStore = scanStateStore
    }

    public func refresh() async {
        guard !isScanning else { return } // single-flight (MainActor serializes the check+set)
        isScanning = true
        defer { isScanning = false }

        let scanner = self.scanner
        let zone = self.zone
        let state = self.scanState
        let source = self.limitSource // bind Sendable values (never capture @MainActor self)
        let store = self.scanStateStore
        let firstLoad = !self.didLoadPersisted
        let result = await Task.detached(priority: .utility) { () -> (ScanState, UsageSnapshot, Bool) in
            // First pass seeds from the persisted cache (decoded off-main) when present;
            // a missing/corrupt/stale cache yields nil → empty base → full cold scan.
            let base = firstLoad ? (store?.load(now: Date()) ?? state) : state
            let updated = scanner.update(base) // grown files read only the appended bytes
            let pricing = scanner.registry.providers.first?.pricing ?? .claude
            let official = source.read(now: Date())
            let snapshot = Aggregator().aggregate(updated.allEvents, using: PeriodBucketer(zone: zone, now: Date()), pricing: pricing, official: official)
            let hasSources = scanner.registry.providers.contains { !$0.dataRoots().isEmpty }
            return (updated, snapshot, hasSources)
        }.value
        self.didLoadPersisted = true
        self.scanState = result.0
        self.snapshot = result.1
        self.hasDataSources = result.2
        self.scheduleSave(result.0) // persist the just-published state, by value, debounced
    }

    /// Persist the latest state ~2 s after activity settles, coalescing bursts.
    /// Mirrors `RefreshController.scheduleRefresh()`: cancel-then-replace a single
    /// task on the main actor, so the newest snapshot wins; the immutable `ScanState`
    /// value is handed off by value, never a shared mutable reference.
    private func scheduleSave(_ snapshot: ScanState) {
        guard let store = scanStateStore else { return }
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            store.save(snapshot, now: Date())
        }
    }
}
