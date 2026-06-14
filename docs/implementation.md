# Implementation guide (for agents)

Work top-to-bottom. Each step has a `[ ]` todo checklist and a **Deliverable** (what must exist and pass before moving on). Keep `swift build` and `swift test` green after every step. Cross-cutting invariants below are non-negotiable in every milestone.

## Cross-cutting invariants

- **Dedup by `message.id`, last-wins**, across all files (global dict). Streaming repeats the same id with identical token tuples.
- **Never sum `message.usage.iterations[]`** — it repeats the top-level counts. Decode only the four top-level usage fields.
- **Skip all-zero-token records;** drop records with no `message.id`; flag unknown models (don't silently zero cost).
- **Off-main scanning.** Parse/aggregate off the main actor; hand an immutable `Sendable` snapshot to the `@MainActor` `UsageStore`. Single-flight refreshes.
- **Headline tokens = input+output by default** (cache-reads are ~97% of the raw total). Limit math uses `billableTotal`.
- **Provider-neutral core.** No Claude-specific code outside `Providers/Claude/`.
- **Zero third-party dependencies.**

---

## M0 — Docs & scaffolding ✅

- [x] `docs/*` written (this set).
- [x] SPM package: `UsageCore` library + `UsageCoreTests`.
- [x] Core models: `TokenCounts`, `TokenDefinition`, `UsageEvent`, `ProviderID`.
- [x] `UsageProvider` protocol + `ProviderRegistry` + `ClaudeProvider` stub.
- [x] `PricingTable` with the Claude table + tests.
- **Deliverable:** `swift build` + `swift test` green. ✅

---

## M1 — Skeleton + one real number ✅

**Goal:** a correct, deduped "Tokens · This Month (input+output)" in the menu bar, off-main, on the real ~521 MB tree. *Validated: 34,793 deduped events, cold scan ~5.4s off-main; GUI confirmed showing 13.1M.*

1. **`JSONLReader`** (`Scanning/JSONLReader.swift`)
   - [x] Streams via `FileHandle` in ~256 KB chunks, splits on `\n`, yields complete lines as `Data`, retains the trailing partial.
   - [x] `seek(toOffset:)` resume; returns the new byte offset (for the M4 incremental scan).
   - **Deliverable:** ✅ tested — multi-line, resume-from-offset, partial-last-line, tiny-chunk fixtures.
2. **Claude record decoding** (`Providers/Claude/ClaudeRecord.swift`, `ClaudeProvider.parse`)
   - [x] Lenient `Decodable` mirror (all fields optional); `usage` decodes only the four top-level fields — `iterations` is intentionally not modeled (would double-count).
   - [x] `parse(line:)` keeps `type == "assistant"` with a non-empty `message.id` and non-zero tokens; tags `provider = .claude`; returns `nil` on anything unparseable.
   - [x] Timestamps parsed by a **manual integer ISO-8601-UTC parser** (`ClaudeTimestamp`), not a `DateFormatter` — faster and `Sendable`-safe; sub-second ignored.
   - **Deliverable:** ✅ tests — dup id, ignored `iterations`, zero / missing-id / non-assistant / corrupt skipped, partial usage. Note: **unknown/`<synthetic>` models are KEPT** (flagged for cost in M3), not skipped.
3. **`UsageScanner`** (`Scanning/UsageScanner.swift`)
   - [x] Enumerates `*.jsonl` recursively (`FileManager.enumerator`); parses → global dedup map keyed by **`(provider, message.id)`**, last-wins → `[UsageEvent]`.
   - [x] Full cold scan (incremental `FileScanState` + mtime/size/byte-offset resume deferred to M4).
   - **Deliverable:** ✅ real tree returns 34,793 deduped events; runs off-main; tested for dedup + missing root.
4. **Aggregation** (`Aggregation/Period.swift`, `PeriodBucketer.swift`, `Aggregator.swift`, `UsageSnapshot.swift`)
   - [x] `Period {today, thisWeek, thisMonth, rolling7, rolling30}`; local-day bucketing by default with a `.utc` toggle; week start respects `firstWeekday`.
   - [x] `Aggregator`: single pass → `TokenCounts` per (period, model) into an immutable `UsageSnapshot`.
   - **Deliverable:** ✅ tests for today/month membership, rolling-30 boundary, this-week, and per-period/per-model sums.
5. **`UsageStore`** (`Aggregation/UsageStore.swift`)
   - [x] `@MainActor @Observable`; `refresh()` runs the scan in a detached task and publishes the `Sendable` snapshot on the main actor; single-flight via an `isScanning` guard.
   - **Deliverable:** ✅ exposes `snapshot.tokens(.thisMonth)`; starts empty/idle (tested).
6. **App** (`App/`, an **SPM executable target** — `swift run inline-usage`)
   - [x] `MenuBarExtra { MenuContentView } label: { Text(model.title) }`, `.menuBarExtraStyle(.window)`; Dock icon hidden via `.accessory` activation policy.
   - [x] Label shows the abbreviated value (K/M/B); dropdown shows the exact grouped value + `in · out · cache-rd` breakdown + Refresh/Quit; "Loading…" until the first scan completes.
   - [x] `--scan-once` headless mode (`Main.swift`) prints per-period totals and exits — the real-data smoke test.
   - **Deliverable:** ✅ launches, shows the correct deduped 13.1M without stalling the menu bar.
   - *Deferred:* the distributable `.app` bundle with `LSUIElement` (M5) and a dedicated `MenuBarLabelView` (M2) — the dev build runs un-bundled via `swift run`.

---

## M2 — Fast switch + settings + real-time

1. **Selection model** (`Metrics/`)
   - [ ] `Metric {tokens, cost, limit5h, limitWeekly}`, `TokenDefinition` (exists), `MetricSelection {provider, metric, period, tokenDefinition}` + `renderTitle(snapshot) -> String` + `renderHeader`.
   - **Deliverable:** unit tests for `renderTitle` across combos.
2. **Number formatting** (`Formatting/NumberFormatting.swift`)
   - [x] K/M/B abbreviation + grouped exact (`UsageFormat.tokens` / `.grouped`) — landed in M1, with tests (999 → "999", 1_500 → "1.5K", 38_214_556 → "38.2M").
   - [ ] Currency and integer-percent formatting (for the cost and plan-limit metrics).
3. **Fast-switch dropdown** (`App/MenuContentView.swift`)
   - [ ] Quick-switch rows (the mockup in `architecture.md`) with live per-row values + checkmark on active; one tap updates selection.
   - [ ] Recompute from in-memory events on switch (no rescan).
   - **Deliverable:** flipping rows updates the menu-bar value instantly.
4. **Real-time refresh** (`App/RefreshController.swift`)
   - [ ] FSEvents recursive watch on each data root + the limit snapshot path; debounce ~300–500 ms; trigger `UsageStore.refresh()`.
   - [ ] Liveness `Timer` so rolling windows advance when idle.
   - [ ] "Updates" setting: Real-time (default) / 1s / 2s / 5s / 10s / 30s.
   - **Deliverable:** writing a new Claude turn updates the menu bar within the debounce window; no main-thread stalls.
5. **Settings + persistence** (`App/SettingsView.swift`, `@AppStorage`)
   - [ ] Keys: `provider, metric, period, tokenDefinition, refreshInterval, bucketTimeZone, …`.
   - **Deliverable:** settings persist across relaunch.

---

## M3 — Cost

- [ ] `CostCalculator` (`Pricing/CostCalculator.swift`): per-model token fold → `PricingTable.cost`; sum across models; collect unknown-model token totals.
- [ ] "Estimated cost" metric (this month / today); dropdown note when unknown-model tokens were excluded.
- [ ] Multi-root: enable the Xcode CodingAssistant dir behind an `includeXcodeDir` toggle (existence-checked).
- **Deliverable:** cost reconciles with the `claude-usage` dashboard for the same period; unknown-model flag shows when relevant.

---

## M4 — Plan limits

1. **Official path** (`Limits/LimitSource.swift`, `scripts/inline-usage-statusline.sh`)
   - [ ] Helper script reads Claude Code's status-line JSON on stdin and writes `{five_hour, seven_day, model, ts}` to `~/.claude/inline-usage/snapshot.json` (passing the input through if wrapping an existing command).
   - [ ] App offers one-click, opt-in registration into `~/.claude/settings.json`'s `statusLine` (wrap any existing command, with explicit consent); watch the snapshot via FSEvents.
   - **Deliverable:** with the hook on and Claude Code active, app 5h/7d % matches `/usage`.
2. **Estimate fallback** (`Limits/FiveHourWindower.swift`, `LimitEstimator.swift`, `PlanLimits.swift`)
   - [ ] Group sorted events into rolling 5h blocks (start at first activity, last 5h). Active block = the one containing `now` (clamp future timestamps).
   - [ ] Budget = custom (user) → P90 of historical block sums (`billableTotal`) → plan multiplier seed. % = used / budget, labeled "estimate".
   - [ ] Weekly = rolling-7-day sum ÷ weekly budget.
   - **Deliverable:** with the hook off, a labeled estimate renders; window-grouping unit tests pass.
3. **Incremental scan** (now that limits need frequent refresh)
   - [ ] `FileScanState{path,mtime,size,byteOffset}` persisted; skip unchanged files; resume grown files from `byteOffset`; re-parse on shrink/rotate.
   - **Deliverable:** a refresh after one new turn touches ~1 file in milliseconds.
- [ ] Menu-bar color/symbol turns orange/red past 80%/100%.

---

## M5 — Polish & notarize

- [ ] `SMAppService.mainApp` launch-at-login toggle.
- [ ] Empty/first-run state (no `~/.claude` → friendly "No data"); timezone setting; refresh-interval polish.
- [ ] **Prereq:** install a Developer ID Application cert. Then: sign (`--options runtime`, no sandbox) → build `.dmg` → `notarytool submit --wait` → `stapler staple` → verify `spctl`. See `distribution.md`.
- **Deliverable:** a notarized `.dmg` that launches clean on a second Mac.

---

## M6 — Additional providers (post-MVP)

- [ ] `Providers/Codex/CodexProvider.swift`, `Providers/Gemini/GeminiProvider.swift` conforming to `UsageProvider`; discover each CLI's data location, record format, and pricing.
- [ ] Add them to `ProviderRegistry`; add provider scope to the menu (per-provider / All).
- **Deliverable:** Codex/Gemini usage shows behind the same UI with no core changes.
