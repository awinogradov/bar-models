# bar-models

A tiny native macOS **menu-bar app** that shows **one** glanceable AI-coding usage number — and lets you switch which one with a single tap, updating in real time.

Inspired by [One Thing](https://sindresorhus.com/one-thing): show a single value, near-zero chrome. Where a full usage dashboard gives you charts, tables, and history, bar-models gives you the one number you actually glance at — one configurable metric, always visible.

- **Claude Code first**, but architected so **Codex CLI / Gemini CLI** and others plug in behind a `UsageProvider` protocol.
- Reads local usage transcripts (`~/.claude/projects/**/*.jsonl`) — no network, no account, all on-device.
- Metrics: **tokens** (today / week / month), **estimated cost**, **% of plan limit** (5h / weekly).

## Status

Early build. See [`docs/`](docs/) for the full design:

- [`docs/prd.md`](docs/prd.md) — product requirements
- [`docs/architecture.md`](docs/architecture.md) — modules, data flow, the provider abstraction
- [`docs/implementation.md`](docs/implementation.md) — step-by-step build guide (todos + deliverables)
- [`docs/features.md`](docs/features.md), [`docs/stack.md`](docs/stack.md), [`docs/claude-calculation.md`](docs/claude-calculation.md), [`docs/plan-limits.md`](docs/plan-limits.md), [`docs/testing.md`](docs/testing.md), [`docs/distribution.md`](docs/distribution.md)

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

See [`docs/distribution.md`](docs/distribution.md) for signing + notarization (`scripts/release.sh`).

Requires macOS 14+ and a Swift 6 toolchain.
