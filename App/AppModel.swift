import AppKit
import Observation
import UsageCore

/// Owns the `UsageStore`, kicks off the first scan, and derives the single
/// displayed string. M1 hardwires the view to Tokens · This Month · input+output;
/// the selectable metric model arrives in M2.
@MainActor
@Observable
final class AppModel {
    let store = UsageStore()

    init() {
        // Menu-bar-only app: no Dock icon (the distributable .app sets LSUIElement;
        // running via `swift run` we set the policy programmatically).
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { await store.refresh() }
    }

    var hasData: Bool { store.snapshot != nil }

    /// The menu-bar label.
    var title: String {
        guard let snapshot = store.snapshot else { return "…" }
        return UsageFormat.tokens(snapshot.tokens(.thisMonth).inputOutput)
    }

    var exactThisMonth: String {
        UsageFormat.grouped(store.snapshot?.tokens(.thisMonth).inputOutput ?? 0)
    }

    var breakdownThisMonth: String {
        let t = store.snapshot?.tokens(.thisMonth) ?? .zero
        return "in \(UsageFormat.tokens(t.input)) · out \(UsageFormat.tokens(t.output)) · cache-rd \(UsageFormat.tokens(t.cacheRead))"
    }

    func refresh() { Task { await store.refresh() } }
}
