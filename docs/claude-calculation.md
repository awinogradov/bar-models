# Claude usage calculation

How `ClaudeProvider` turns transcripts into tokens and cost. (Validated against a real `~/.claude`: ~1,458 files, ~217k lines, ~521 MB; cache-reads ≈ 97% of total tokens.)

## Data location

- `~/.claude/projects/**/*.jsonl` — one JSON object per line.
- Optional (M3, toggle): `~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects/**/*.jsonl`.
- All roots are existence-checked; a missing root is simply skipped.

## Record shape (only what we read)

```jsonc
{
  "type": "assistant",                         // keep only "assistant"
  "timestamp": "2026-05-22T08:15:22.881Z",     // ISO-8601 UTC
  "sessionId": "…", "cwd": "…",                // context (not required for tokens)
  "message": {
    "id": "msg_…",                             // DEDUP KEY (required)
    "model": "claude-opus-4-8",
    "usage": {
      "input_tokens": 1234,
      "output_tokens": 567,
      "cache_creation_input_tokens": 8901,
      "cache_read_input_tokens": 23456,
      "iterations": [ /* … repeats the same counts — DO NOT SUM … */ ]
    }
  }
}
```

We decode **only** the four top-level `usage` fields. Everything else is optional in the decoder so malformed/partial lines never crash parsing (`parse` returns `nil` and the line is skipped).

## Two double-count traps

1. **Streaming repeats `message.id`.** The same turn is logged multiple times (observed up to 7×) with identical token tuples. Keep a **global `[message.id: UsageEvent]` map, last-wins**. Records without an id are dropped.
2. **`usage.iterations[]` repeats the totals.** It's a breakdown of the already-reported top-level usage. Never sum it.

Also: skip records where all four counts are 0; flag unknown models (don't zero their cost silently).

## Token definitions

Because cache-reads dominate, the *definition* of "tokens" matters:

| Definition | Sum | Use |
|---|---|---|
| `inputOutputOnly` | input + output | **Headline default** — intuitive "usage". |
| `withCacheWrite` | input + output + cache-write | When cache creation matters. |
| `billableTotal` | input + output + cache-write + cache-read | Cost-correlated; used by the limit math. |

Implemented in `TokenCounts.value(for:)`.

## Pricing (per million tokens, authoritative 2026-06)

cache-write 5m = 1.25× input, cache-read = 0.1× input.

| Model ID | input | output | cache-write 5m | cache-read |
|---|---|---|---|---|
| `claude-fable-5` | 10 | 50 | 12.50 | 1.00 |
| `claude-opus-4-8` | 5 | 25 | 6.25 | 0.50 |
| `claude-opus-4-7` | 5 | 25 | 6.25 | 0.50 |
| `claude-sonnet-4-6` | 3 | 15 | 3.75 | 0.30 |
| `claude-haiku-4-5(-20251001)` | 1 | 5 | 1.25 | 0.10 |

Model match order (`PricingTable.rate(for:)`): exact id → longest id prefix → family keyword (`fable`/`opus`/`sonnet`/`haiku`) → `nil` (unknown). Cost = Σ over models of `Σ bucket × rate / 1e6`. Unknown-model tokens are surfaced separately, not folded into cost. Estimated cost is **API-equivalent** — Pro/Max subscribers don't pay it directly.

## Periods & timezone

Periods: today, this week, this month, rolling 7d, rolling 30d. **Default bucketing is the user's local calendar day** (a "today" should mean the user's day), via `Calendar.current`; a UTC toggle exists for parity with tools that bucket by UTC date string. Week start respects `Calendar.current.firstWeekday`. Near midnight, local and UTC differ — documented, user-selectable.

## Timestamps

ISO-8601 UTC with fractional seconds. Parse with a cached `en_US_POSIX` / GMT `DateFormatter` (`yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX`) plus a no-fractional-seconds fallback. `ISO8601DateFormatter` is avoided (slower, historically finicky about the fractional-seconds option).

## 5-hour window (limit estimate)

Sort deduped events ascending. A block starts at the first event not within 5h of the current block's start and contains events in `[start, start+5h)`. The active block is the one containing `now` (clamp timestamps `> now` for clock skew). Used tokens = Σ `billableTotal` in the active block. See `plan-limits.md` for how that becomes a percentage.
