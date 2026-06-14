# Testing

## Strategy

`UsageCore` is pure and UI-free, so the bulk of testing is fast, deterministic unit tests run with **Swift Testing** (`swift test`). The app layer is verified manually (menu-bar behavior, real-time updates) and by cross-checking totals against the `claude-usage` dashboard.

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

Run: `swift test`. Keep green after every step.

## Cross-check against `claude-usage`

Get the app's side with `swift run inline-usage --scan-once` — it prints **all-time per-model totals** (input / output / cacheWrite / cacheRead). Sum the dashboard's `http://localhost:8080/api/data` `daily_by_model` across all days (timezone-independent) and compare per model; the app's `cacheWrite` maps to the dashboard's `cache_creation`. Trigger the dashboard's own rebuild first (`POST /api/rescan`) so both read the same tree.

**Result (2026-06-14):** stable models (`fable-5`, `opus-4-7`, `sonnet-4-6`) matched the dashboard **exactly** across all four token buckets. The actively-used models (`opus-4-8` = current session, `haiku-4-5` = subagents) differed only by the turns written between the two scans — whichever tool scanned later was slightly ahead — confirming identical methodology, with the deltas explained entirely by scan timing, not by a parsing/dedup difference.

## Manual / app verification

- **Real-time:** trigger a new Claude turn; the menu-bar value updates within the debounce window; no main-thread stall on the full ~521 MB tree.
- **Fast switch:** flipping dropdown rows changes the value instantly (no rescan).
- **Plan limits:** with the hook enabled and Claude Code active, the shown 5h/7d % matches `/usage` and the status line; with it off, the estimate renders and is labeled.
- **First run:** with no `~/.claude`, the app shows a friendly "No data" state and doesn't crash.
- **Performance:** cold scan completes in a few seconds off-main; incremental refresh (M4) after one new turn is sub-second.

## Performance fixtures

Keep one large synthetic tree (script-generated, not committed) to benchmark cold scan and incremental refresh; assert the incremental path touches only changed files.
