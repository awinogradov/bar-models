# Features

## The one thing

The menu bar shows a single value. That's the product. Everything else is in service of choosing *which* value and keeping it correct and live.

## Metric × period matrix

The displayed value is a small config: **provider × metric × period × token-definition**.

| Metric | Periods offered | Notes |
|---|---|---|
| Tokens | Today · This Week · This Month · Rolling 7d · Rolling 30d | Default. Token definition selects which buckets count. |
| Estimated cost | This Month · Today | USD via the pricing table; API-equivalent. |
| Plan limit — 5h | (window-implied) | % of the rolling 5-hour window. |
| Plan limit — Weekly | (window-implied) | % of the rolling 7-day window. |

**Token definition** (for the tokens metric):
- `inputOutputOnly` — **default**. The intuitive "how much did I use" number.
- `withCacheWrite` — adds cache-creation.
- `billableTotal` — input + output + cache write + cache read. Cost-correlated, but ~97% cache-read, so it's a big number that barely tracks effort. Also what the limit math uses internally.

## Scope: all models, combined

The displayed value sums across **all models** (Opus + Sonnet + Haiku + Fable) for the period — one number, true to "one thing". A Haiku token and an Opus token count equally here, which is fine for a raw token glance but is exactly why **cost** is the more meaningful cross-model number (computed per-model then summed, never from a blended token count) and why the dropdown gains a **per-model breakdown** in M3. Pinning the headline to a single model (a model *scope*) may join the provider scope later. The per-model split already lives in the snapshot (`PeriodTotals.byModel`); only the UI surfacing is pending.

## Fast switch (core UX)

A one-tap quick-switch list lives directly in the dropdown — no Settings trip. Each row shows its live value; the active one is checkmarked. Tapping a row changes the menu-bar value **instantly**, recomputed from in-memory events (no rescan). The header shows the exact current number plus the per-bucket token breakdown, so the headline is never mistaken for "all tokens".

## Real-time refresh

Updates are event-driven, not polled:
- **FSEvents** watches each provider's data root (and the limit snapshot file). A new turn → debounced (~300–500 ms) incremental rescan → menu bar updates in well under a second.
- A light **timer** advances clock-based rolling windows (5h/weekly) when idle.
- An explicit **"Updates"** setting offers `Real-time` (default) / `1s` / `2s` / `5s` / `10s` / `30s`.

## Estimated cost

Per-model token sums × an authoritative price table (input / output / cache-write / cache-read per million). Unknown models are flagged and excluded (never silently zeroed). Cost is API-equivalent; the UI notes that Pro/Max subscribers don't pay it directly. See `05-claude-calculation.md`.

## Plan-limit %

Two sources, official first:
- **Official (exact):** an opt-in status-line hook captures Claude Code's own `rate_limits.five_hour/seven_day.used_percentage`.
- **Estimate (labeled):** rolling-window token sums ÷ a calibrated budget when the hook isn't active.

See `06-plan-limits.md`.

## Settings

Small popover: which metric/period/definition, provider scope, plan + custom budget, updates interval, timezone (local/UTC) for period boundaries, include-Xcode-dir toggle, enable-live-limits, launch-at-login, automatically-check-for-app-updates.

The dropdown also carries a **Check for Updates…** action; the app ships with [Sparkle](https://sparkle-project.org) so a new release installs in place instead of requiring a re-download (see [`09-distribution.md`](09-distribution.md)).

## Provider scope (forward-looking)

Claude only in the MVP. The menu will gain a provider scope (Claude / Codex / Gemini / All) once additional providers land — the rest of the UI is unchanged.
