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

    public init(scanner: UsageScanner = UsageScanner()) {
        self.scanner = scanner
    }

    public func refresh() async {
        guard !isScanning else { return } // single-flight (MainActor serializes the check+set)
        isScanning = true
        defer { isScanning = false }

        let scanner = self.scanner
        let zone = self.zone
        snapshot = await Task.detached(priority: .utility) {
            let events = scanner.scan()
            return Aggregator().aggregate(events, using: PeriodBucketer(zone: zone, now: Date()))
        }.value
    }
}
