# Bar Models

A tiny native macOS **menu-bar app** that shows **one** glanceable AI-coding usage number — and lets you switch which one with a single tap, updating in real time.

Inspired by [One Thing](https://sindresorhus.com/one-thing): show a single value, near-zero chrome. Where a full usage dashboard gives you charts, tables, and history, Bar Models gives you the one number you actually glance at — one configurable metric, always visible.

- **Claude Code first**, but architected so **Codex CLI / Gemini CLI** and others plug in behind a `UsageProvider` protocol.
- Reads local usage transcripts (`~/.claude/projects/**/*.jsonl`) — no network, no account, all on-device.
- Metrics: **tokens** (today / week / month), **estimated cost**, **% of plan limit** (5h / weekly).

## Documentation

The design is written up as numbered chapters in [`docs/`](docs/):

| Doc | What it covers |
| --- | --- |
| [`01-prd.md`](docs/01-prd.md) | Problem, solution, target user, goals & non-goals, success criteria, milestones, and principles. |
| [`02-features.md`](docs/02-features.md) | The metric × period matrix, token definitions, fast-switch UX, real-time refresh, cost, and plan-limit %. |
| [`03-architecture.md`](docs/03-architecture.md) | Modules, data flow, and the provider abstraction — the App target on top of the `UsageCore` engine. |
| [`04-stack.md`](docs/04-stack.md) | Language/platform choices, the key system APIs, and the considered-and-rejected alternatives. |
| [`05-claude-calculation.md`](docs/05-claude-calculation.md) | How `ClaudeProvider` turns transcripts into tokens and cost: data location, record shape, dedup, pricing. |
| [`06-plan-limits.md`](docs/06-plan-limits.md) | Official % via the status-line hook vs. the labeled estimate fallback, and the honesty rules. |
| [`07-implementation.md`](docs/07-implementation.md) | Step-by-step build guide: per-milestone todos, deliverables, and the cross-cutting invariants. |
| [`08-testing.md`](docs/08-testing.md) | Unit-test scope, the reference-dashboard cross-check, and manual/app verification. |
| [`09-distribution.md`](docs/09-distribution.md) | Signing, Hardened Runtime, DMG, notarization, and stapling for a downloadable build. |

## Project structure

```
bar-models/
├── App/                       # SwiftUI menu-bar app — executable target `bar-models`
│   ├── BarModelsApp.swift
│   ├── AppModel.swift
│   ├── MenuContentView.swift
│   ├── SettingsView.swift
│   ├── RefreshController.swift
│   ├── LaunchAtLogin.swift
│   └── Main.swift
├── Sources/UsageCore/         # provider-neutral engine — SPM library, no UI
│   ├── Model/                 # TokenCounts · UsageEvent · ProviderID
│   ├── Providers/             # UsageProvider · ProviderRegistry · Claude/
│   ├── Scanning/              # JSONLReader · UsageScanner (+ incremental) · ScanState
│   ├── Aggregation/           # Period · Aggregator · UsageStore · DataAvailability
│   ├── Pricing/               # PricingTable · CostCalculator
│   ├── Metrics/               # MetricSelection
│   ├── Formatting/            # NumberFormatting
│   └── Limits/                # FiveHourWindower · LimitEstimator · LimitStatus
├── Tests/UsageCoreTests/      # Swift Testing unit tests
├── docs/                      # numbered chapters (see Documentation)
├── scripts/                   # package-app.sh · release.sh
├── Package.swift
└── VERSION
```

## Build

```sh
swift build                       # build UsageCore (the engine) + the app
swift test                        # run the unit tests
swift run bar-models              # run the menu-bar app (dev, un-bundled)
swift run bar-models --scan-once  # headless: print per-period totals and exit
```

To produce a distributable `.app` bundle (universal, menu-bar-only via `LSUIElement`):

```sh
scripts/package-app.sh            # ad-hoc signed, for local use
```

See [`09-distribution.md`](docs/09-distribution.md) for signing + notarization (`scripts/release.sh`).

Requires macOS 14+ and a Swift 6 toolchain.
