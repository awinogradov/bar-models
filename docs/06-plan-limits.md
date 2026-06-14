# Plan limits

The most useful "one thing" for a subscriber is "how close am I to my limit right now?". This is also the hardest to do honestly — so we use **official data first** and a **clearly-labeled estimate** only as a fallback.

## What Anthropic actually publishes

- A **rolling 5-hour window** (starts at your first message, rolls) and **weekly caps** (introduced Aug 28, 2025; an overall weekly cap plus a model-specific one on Max).
- Only **relative multipliers** — Pro 1× / Max 5× / Max 20× — and the *structure*. Exact per-window token budgets are **not** published, and they change over time (e.g. the 5h limits were doubled May 6, 2026). So any hardcoded token budget would be wrong.

## Primary: official % via the status-line hook (exact)

Claude Code pipes JSON to any configured status-line command, and that JSON includes the real numbers:

```jsonc
{ "model": { "display_name": "…" },
  "rate_limits": {
    "five_hour": { "used_percentage": 42 },
    "seven_day": { "used_percentage": 31 } } }
```

So we capture it:

1. Ship `scripts/bar-models-statusline.sh` — reads that JSON on stdin, writes `{five_hour, seven_day, model, ts}` to `~/.claude/bar-models/snapshot.json`, and (if wrapping an existing status-line command) passes the input through so the user's existing status line still renders.
2. The app offers a **one-click, opt-in** "Enable live limits": with explicit consent it registers the helper as the `statusLine` command in `~/.claude/settings.json`, wrapping any command already there.
3. The app watches the snapshot file (FSEvents) and shows exact "5h 42% · 7d 31%".

This is the only write the app ever makes to Claude's files, and only on explicit opt-in.

## Fallback: estimate (always labeled)

When there's no fresh snapshot (hook not enabled, or Claude Code not running):

- Group events into rolling 5-hour blocks (see `05-claude-calculation.md`), sum the active block's `billableTotal`.
- **Budget** = custom value the user entered → else P90 of historical block sums (auto-calibration, à la community monitors) → else the plan multiplier against a conservative seed.
- `% = used / budget`, rendered with an explicit "estimate" label and low/normal confidence based on history depth.
- Weekly = rolling-7-day `billableTotal` ÷ weekly budget.

## Honesty rules

- Never present the estimate as authoritative; always label it and show its basis (plan and/or P90 budget).
- Prefer the official snapshot whenever it's fresh.
- The model-specific weekly cap (e.g. Opus) isn't separately estimated in v1 — note that the weekly figure is the overall cap.
- Limits change; the official path is robust to that, the estimate is best-effort.

## Not used

- `GET /v1/organizations/usage_report/claude_code` is an **org-admin** API (needs an Admin API key); irrelevant for an individual subscriber reading local files.
- `/usage` inside Claude Code is interactive-only (not a file we can read).
