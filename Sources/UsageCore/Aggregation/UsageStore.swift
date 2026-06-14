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
        let result = await Task.detached(priority: .utility) { () -> (ScanState, UsageSnapshot) in
            let updated = scanner.update(state) // first pass full; later passes read only appended bytes
            let snapshot = Aggregator().aggregate(updated.allEvents, using: PeriodBucketer(zone: zone, now: Date()))
            return (updated, snapshot)
        }.value
        self.scanState = result.0
        self.snapshot = result.1
    }
}
