import AppKit
import Observation
import UsageCore

/// Owns the `UsageStore`, the current `MetricSelection`, and settings; derives
/// the single displayed value and drives real-time refresh. Switching the
/// metric/period recomputes from the in-memory snapshot — no rescan. Persistence
/// is manual `UserDefaults` (avoids mixing `@AppStorage` with `@Observable`).
@MainActor
@Observable
final class AppModel {
    let store = UsageStore()
    var selection: MetricSelection
    var zone: PeriodBucketer.Zone
    var refreshInterval: RefreshInterval

    private var refresher: RefreshController?

    init() {
        selection = AppModel.loadSelection()
        zone = AppModel.loadZone()
        refreshInterval = AppModel.loadInterval()
        store.zone = zone
        NSApplication.shared.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
        Task { await store.refresh() }
        startWatching()
    }

    // MARK: Display

    var hasData: Bool { store.snapshot != nil }
    var title: String { selection.render(from: store.snapshot) }
    var headerTitle: String { selection.header }
    var headerValue: String { selection.renderExact(from: store.snapshot) }

    var breakdown: String {
        guard selection.metric == .tokens, let t = store.snapshot?.tokens(selection.period) else { return "" }
        return "in \(UsageFormat.tokens(t.input)) · out \(UsageFormat.tokens(t.output)) · cache-rd \(UsageFormat.tokens(t.cacheRead))"
    }

    // MARK: Fast switch

    /// The quick-switch rows. M2 offers the token periods; cost (M3) and plan
    /// limits (M4) join the list in their milestones.
    var menuOptions: [MetricSelection] {
        [Period.today, .thisWeek, .thisMonth, .rolling30].map {
            MetricSelection(provider: selection.provider, metric: .tokens, period: $0, tokenDefinition: selection.tokenDefinition)
        }
    }

    func isSelected(_ option: MetricSelection) -> Bool {
        option.metric == selection.metric && option.period == selection.period
    }

    func value(for option: MetricSelection) -> String { option.render(from: store.snapshot) }

    func select(_ option: MetricSelection) {
        selection = option
        saveSelection()
    }

    // MARK: Settings

    func setTokenDefinition(_ definition: TokenDefinition) {
        selection.tokenDefinition = definition
        saveSelection()
    }

    func setZone(_ newZone: PeriodBucketer.Zone) {
        zone = newZone
        store.zone = newZone
        UserDefaults.standard.set(newZone.rawValue, forKey: Keys.zone)
        refresh() // re-bucket against the new day boundaries
    }

    func setRefreshInterval(_ interval: RefreshInterval) {
        refreshInterval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: Keys.interval)
        refresher?.start(roots: AppModel.watchRoots(), interval: interval)
    }

    func refresh() { Task { await store.refresh() } }

    // MARK: Watching

    private func startWatching() {
        let controller = RefreshController { [weak self] in self?.refresh() }
        controller.start(roots: AppModel.watchRoots(), interval: refreshInterval)
        refresher = controller
    }

    private static func watchRoots() -> [URL] {
        ProviderRegistry.default.providers.flatMap { $0.dataRoots() }
    }

    // MARK: Persistence

    private enum Keys {
        static let selection = "selection"
        static let zone = "bucketTimeZone"
        static let interval = "refreshInterval"
    }

    private func saveSelection() {
        UserDefaults.standard.set(selection.jsonString, forKey: Keys.selection)
    }

    private static func loadSelection() -> MetricSelection {
        UserDefaults.standard.string(forKey: Keys.selection).flatMap(MetricSelection.init(jsonString:)) ?? .default
    }

    private static func loadZone() -> PeriodBucketer.Zone {
        UserDefaults.standard.string(forKey: Keys.zone).flatMap(PeriodBucketer.Zone.init(rawValue:)) ?? .local
    }

    private static func loadInterval() -> RefreshInterval {
        UserDefaults.standard.string(forKey: Keys.interval).flatMap(RefreshInterval.init(rawValue:)) ?? .realtime
    }
}
