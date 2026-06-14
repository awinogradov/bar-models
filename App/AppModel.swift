import AppKit
import Observation
import UsageCore

/// One row of the per-model breakdown shown in the dropdown.
struct ModelLine: Identifiable, Equatable {
    let id: String
    let name: String
    let value: String
}

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

    private let pricing = ProviderRegistry.default.providers.first?.pricing ?? .claude
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

    /// Per-model breakdown of the current selection (tokens or cost), largest first.
    var modelBreakdown: [ModelLine] {
        guard let snapshot = store.snapshot else { return [] }
        let totals = snapshot.totals(for: selection.period)
        switch selection.metric {
        case .tokens:
            return totals.byModel
                .map { (model: $0.key, raw: $0.value.value(for: selection.tokenDefinition)) }
                .filter { $0.raw > 0 }
                .sorted { $0.raw > $1.raw }
                .map { ModelLine(id: $0.model, name: AppModel.shortModel($0.model), value: UsageFormat.tokens($0.raw)) }
        case .cost:
            return CostCalculator(pricing: pricing).cost(of: totals.byModel).byModel
                .filter { $0.value > 0 }
                .sorted { $0.value > $1.value }
                .map { ModelLine(id: $0.key, name: AppModel.shortModel($0.key), value: UsageFormat.cost($0.value)) }
        case .limit5h, .limitWeekly:
            return []
        }
    }

    /// Shown under a cost view when tokens from unpriced models were excluded.
    var unknownModelNote: String? {
        guard selection.metric == .cost, let snapshot = store.snapshot else { return nil }
        let tokens = snapshot.totals(for: selection.period).unknownModelTokens
        return tokens > 0 ? "excludes \(UsageFormat.tokens(tokens)) tokens from unpriced models" : nil
    }

    // MARK: Fast switch

    var menuOptions: [MetricSelection] {
        let provider = selection.provider
        let definition = selection.tokenDefinition
        func tokens(_ period: Period) -> MetricSelection {
            MetricSelection(provider: provider, metric: .tokens, period: period, tokenDefinition: definition)
        }
        func cost(_ period: Period) -> MetricSelection {
            MetricSelection(provider: provider, metric: .cost, period: period, tokenDefinition: definition)
        }
        return [tokens(.today), tokens(.thisWeek), tokens(.thisMonth), tokens(.rolling30),
                cost(.thisMonth), cost(.today)]
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
        refresh()
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

    // MARK: Helpers

    /// "claude-opus-4-8" → "opus-4-8"; "claude-haiku-4-5-20251001" → "haiku-4-5".
    static func shortModel(_ model: String) -> String {
        var name = model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
        if let range = name.range(of: #"-\d{8}$"#, options: .regularExpression) { name.removeSubrange(range) }
        return name
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
