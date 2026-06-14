# Architecture

## Two targets

- **`UsageCore`** — a pure-Swift SPM library: parsing, dedup, aggregation, pricing, limits, and the "one thing" selection model. **No UI imports**, so it's unit-testable with `swift test`. This is where all the logic lives.
- **App** — a thin SwiftUI `MenuBarExtra` target (built in Xcode) that depends on `UsageCore`, owns the refresh loop, and renders one value.

## Data flow

```
  Claude Code        Codex CLI*        Gemini CLI*         status-line hook
  ~/.claude/         ~/.codex/*        ~/.gemini/*         snapshot.json
   projects/                                               (opt-in, M4)
       │                 │                 │                    │
       ▼ ①               ▼                 ▼                    ▼ ③
  ┌──────────────────────────────────────────────────┐   ┌───────────────┐
  │ Provider registry — UsageProvider protocol        │   │ LimitSource   │
  │ ● ClaudeProvider   ○ Codex*   ○ Gemini*           │   │ official %    │
  └───────────────────────────┬──────────────────────┘   └───────┬───────┘
                              │ ② normalized UsageEvent           │ ④
                              └───────────────┬───────────────────┘
                                              ▼
  ┌───────────────────────────────────────────────────────────────────┐
  │ UsageCore — Scanner · Aggregator · UsageStore · MetricSelection     │
  └──────────────────────────────┬────────────────────────────────────┘
                                  │ ⑤ @Observable snapshot
                                  ▼
  ┌───────────────────────────────────────────────────────────────────┐
  │ App (SwiftUI) — MenuBarExtra · MenuContentView (fast switch)        │
  └──────────────────────────────┬────────────────────────────────────┘
                                  │ ⑥ one chosen value
                                  ▼
                       ┌────────────────────────┐
                       │   menu bar:  ◔ 38.2M    │
                       └────────────────────────┘
```

**Flow Legend:**
- ① Each provider's CLI appends usage to its own local files (`*` = future provider; format discovered when implemented).
- ② Each `UsageProvider` parses records into a normalized `UsageEvent` (tagged with `provider`); the scanner dedups + aggregates.
- ③ (M4, opt-in) a status-line hook writes Claude Code's official rate-limit % to a snapshot file.
- ④ `LimitSource` reads the official snapshot when present (else a labeled estimate).
- ⑤ `RefreshController` (FSEvents-driven, debounced) publishes an `@Observable` snapshot.
- ⑥ `MetricSelection.renderTitle` turns the snapshot into the single menu-bar string.

## Modules

```
┌──────────────────────── App target (SwiftUI, Xcode) ────────────────────────┐
│ BarModelsApp · MenuBarLabelView · MenuContentView · SettingsView             │
│ AppModel · RefreshController (FSEvents + debounce + liveness tick)           │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                     │ depends on
┌───────────────────────────────────▼──── UsageCore (pure Swift, tested) ──────┐
│ Providers/   UsageProvider · ProviderRegistry · Claude/ClaudeProvider         │
│ Scanning/    JSONLReader · UsageScanner · FileScanState                       │
│ Aggregation/ UsageStore · PeriodBucketer · Aggregator                         │
│ Pricing/     PricingTable · CostCalculator                                    │
│ Limits/      FiveHourWindower · LimitEstimator · PlanLimits · LimitSource     │
│ Metrics/     Metric · Period · TokenDefinition · MetricSelection              │
│ Model/       UsageEvent · TokenCounts · ProviderID                            │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Refresh sequence (real-time)

```
FSEvents     RefreshController    UsageScanner     UsageStore       MenuBarExtra
   │ change       │                   │                │                │
   │─────────────▶│ debounce ~300ms   │                │                │
   │              │──────────────────▶│ incremental    │                │
   │              │                   │ parse + dedup   │                │
   │              │                   │───────────────▶│ publish        │
   │              │                   │                │───────────────▶│ renderTitle
```

A light timer also fires on the chosen interval so clock-based rolling windows (5h/weekly) advance even with no new writes. All scanning runs off-main; results are handed to the `@MainActor` `UsageStore` as an immutable snapshot. Refreshes are single-flighted (no overlapping scans).

## The provider abstraction (how to add Codex / Gemini)

Everything provider-specific is behind one protocol (`Sources/UsageCore/Providers/UsageProvider.swift`):

```swift
protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    func dataRoots() -> [URL]              // existence-checked
    func parse(line: Data) -> UsageEvent?  // → normalized, never throws
    var pricing: PricingTable { get }
    // var limitSource: LimitSource? { get } // added in M4
}
```

`UsageEvent`, `TokenCounts`, `Aggregator`, `MetricSelection`, and all rendering are provider-agnostic. Adding a provider = a new folder under `Providers/` + one line in `ProviderRegistry`. The menu gains an optional provider scope (default "Claude"; later "All" / per-provider). Discovering a new CLI's data location, record format, and pricing is that provider's work — it never touches the core.

## Menu-bar dropdown (the fast-switch UX)

```
┌────────────────────────────────────────┐
│ Tokens · This Month                    │
│ 38,214,556                             │
│ in 6.1M · out 1.2M · cache-rd 30.9M    │
├────────────────────────────────────────┤
│ Show in menu bar                       │
│   Tokens — Today                  1.8M │
│   Tokens — This Week              9.4M │
│ ✓ Tokens — This Month            38.2M │
│   Cost — This Month              $4.21 │
│   Plan limit — 5h                  42% │
│   Plan limit — Weekly              31% │
├────────────────────────────────────────┤
│ Settings…                           ⌘, │
│ Quit                                ⌘Q │
└────────────────────────────────────────┘
```

One tap on a row changes the menu-bar value instantly — recomputed from in-memory events, no rescan. Each row shows its live value; the active one is checkmarked. The header shows the exact number plus the token breakdown so the headline is never mistaken for "all tokens".
