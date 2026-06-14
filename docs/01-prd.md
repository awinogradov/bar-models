# PRD — bar-models

## Problem

Developers on Claude Code (and soon other AI-coding CLIs) have no always-on sense of *how much they're using*. A full usage dashboard is accurate, but it's something you have to stop and open. The information people actually want moment-to-moment is a single number: "how many tokens this month?", "how close am I to my limit right now?". A dashboard is the wrong shape for a glance.

## Solution

A tiny native macOS menu-bar app that shows **exactly one** usage value, always visible, switchable in one tap, updating in real time. It borrows the *One Thing* philosophy (a single line of text, no chrome) and the local-transcript data model of a full usage dashboard, and meets in the middle.

## Target user

A developer who uses Claude Code daily on macOS, on a Pro/Max subscription (or API), who wants ambient awareness of usage without opening a dashboard. Secondary: users of multiple AI CLIs who want one combined view later.

## Goals

- Show one configurable metric in the menu bar: tokens (today/week/month), estimated cost, or % of plan limit (5h / weekly).
- Switch the displayed metric in one tap, from the menu itself.
- Update in **real time** as new usage is written (sub-second, no manual refresh).
- 100% local: read on-device transcripts, no network, no account, no telemetry.
- Be tiny and idiomatic: native SwiftUI, zero third-party dependencies, ~single-digit MB.
- Ship as a notarized `.dmg` anyone can run.

## Non-goals (v1)

- Not a dashboard. No charts, tables, history views — a full usage dashboard is the right shape for those.
- No multiple values at once in the menu bar (the whole point is *one* thing).
- No org/admin analytics, no cloud sync, no accounts.
- No write access to Claude data (read-only; the only optional write is an opt-in status-line hook the user explicitly enables).

## Success criteria

- A correct, deduplicated "tokens this month" appears in the menu bar within a couple seconds of launch, on a real ~500 MB transcript tree, without stalling the UI.
- Switching metrics is instant (no rescan).
- When the opt-in status-line hook is enabled, the shown 5h/weekly % matches Claude Code's own `/usage` and status line; without it, a clearly-labeled estimate is shown.
- Token/cost totals reconcile with an external reference dashboard for the same period.

## Scope by milestone

See [`07-implementation.md`](07-implementation.md) for the step-by-step build. High level:

- **M0** Docs + engine scaffold (`UsageProvider` protocol, core models, pricing).
- **M1** Real parsing + one number (tokens · this month).
- **M2** Fast in-menu switch + settings + real-time refresh.
- **M3** Estimated cost.
- **M4** Plan-limit % (official status-line snapshot, estimate fallback).
- **M5** Polish + launch-at-login + notarized `.dmg`.
- **M6** (post-MVP) Codex / Gemini providers.

## Principles

- **One thing.** If a feature adds a second number to the menu bar, it's wrong.
- **Honest numbers.** Cache-reads dominate raw totals, so the headline is input+output by default; estimates are always labeled "estimate"; unknown models are flagged, not silently zeroed.
- **Provider-neutral core.** Claude-specific code lives behind one protocol, so other providers (Codex, Gemini) plug in without touching the engine.
