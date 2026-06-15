# Testing

## Strategy

`UsageCore` is pure and UI-free, so the bulk of testing is fast, deterministic unit tests run with **Swift Testing** (`swift test`). The app layer is verified manually (menu-bar behavior, real-time updates) and by cross-checking totals against an external reference dashboard.

## Unit tests (`Tests/UsageCoreTests/`)

Use small hand-built JSONL fixtures (`Fixtures/*.jsonl`) covering the traps:

- **Dedup** — same `message.id` repeated (identical tokens) collapses to one event.
- **`iterations` trap** — a record with a populated `usage.iterations[]` counts only the top-level usage.
- **Skip-zero** — all-zero-token record is dropped.
- **Missing id / wrong type** — `type != "assistant"` or no `message.id` is dropped.
- **Unknown model** — `<synthetic>`/unknown returns `nil` rate; cost excludes it and flags it.
- **Corrupt / partial line** — unparseable or truncated trailing line is skipped, not fatal.
- **Pricing** — exact / prefix / keyword match; cost per million (e.g. 1M output on opus-4-8 = $25). *(present)*
- **TokenCounts** — addition, `value(for:)` per definition, `isZero`. *(present)*
- **Period bucketing** — local-vs-UTC month/day edges; week start via `firstWeekday`.
- **5-hour windower** — block boundaries (events exactly at +5h), active-block selection, future-timestamp clamp.
- **Formatting** — K/M/B thresholds, currency, percent.
- **Provider tagging** — events carry the right `ProviderID`.
- **Official limits** — `LimitSource` freshness boundary (`<=`), window-reset drop, 0–100 → 0…1 conversion, absent/malformed; `Aggregator` `official ?? estimate` override + stale-snapshot fallback; `UsageStore` publishes official when fresh.
- **Status-line hook** — the script, driven as a subprocess with a temp `HOME`, writes the snapshot from `rate_limits`, nulls when absent, finds `jq` on a minimal `PATH`, and passes stdin through a wrapped command (exit status preserved).
- **settings.json transform** — `StatusLineConfig` enable wraps/creates idempotently; disable restores the exact prior (args + quotes) or removes it; sibling keys preserved; unparseable settings throw.
- **Persisted scan state** — `UsageEvent`/`ScanState` Codable round-trip (including the `\u{1}` dedup keys and full-range `UInt64`); the versioned cache discards corrupt / wrong-version / stale / missing files and prunes cursors for vanished files; `UsageStore` seeds its first scan from the persisted state.
- **Shrink / rotate** — a replaced file (new inode or birthtime, even with a reused inode) and a shrunk file both re-read from offset 0, while a plain append still resumes.

Run: `swift test`. Keep green after every step.

## Cross-check against a reference dashboard

Get the app's side with `swift run bar-models --scan-once` — it prints **all-time per-model totals** (input / output / cacheWrite / cacheRead). Compare those per-model figures against a trusted reference (another local-transcript usage tool, or the provider's own reporting) over the same `~/.claude` tree; note the app's `cacheWrite` is the provider's `cache_creation`. Make sure both sides scan the same snapshot before comparing.

**Result (2026-06-14):** stable models (`fable-5`, `opus-4-7`, `sonnet-4-6`) matched the reference **exactly** across all four token buckets. The actively-used models (`opus-4-8` = current session, `haiku-4-5` = subagents) differed only by the turns written between the two scans — whichever tool scanned later was slightly ahead — confirming identical methodology, with the deltas explained entirely by scan timing, not by a parsing/dedup difference.

## Manual / app verification

- **Real-time:** trigger a new Claude turn; the menu-bar value updates within the debounce window; no main-thread stall on the full ~521 MB tree.
- **Fast switch:** flipping dropdown rows changes the value instantly (no rescan).
- **Plan limits:** with the hook enabled and Claude Code active, the shown 5h/7d % matches `/usage` and the status line; with it off, the estimate renders and is labeled.
- **First run:** with no `~/.claude`, the app shows a friendly "No data" state and doesn't crash.
- **Performance:** cold scan completes in a few seconds off-main; incremental refresh (M4) after one new turn is sub-second.

## Performance fixtures

Keep one large synthetic tree (script-generated, not committed) to benchmark cold scan and incremental refresh; assert the incremental path touches only changed files.
