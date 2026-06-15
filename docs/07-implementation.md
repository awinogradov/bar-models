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
6. **App** (`App/`, an **SPM executable target** — `swift run bar-models`)
   - [x] `MenuBarExtra { MenuContentView } label: { Text(model.title) }`, `.menuBarExtraStyle(.window)`; Dock icon hidden via `.accessory` activation policy.
   - [x] Label shows the abbreviated value (K/M/B); dropdown shows the exact grouped value + `in · out · cache-rd` breakdown + Refresh/Quit; "Loading…" until the first scan completes.
   - [x] `--scan-once` headless mode (`Main.swift`) prints per-period totals and exits — the real-data smoke test.
   - **Deliverable:** ✅ launches, shows the correct deduped 13.1M without stalling the menu bar.
   - *Deferred:* the distributable `.app` bundle with `LSUIElement` (M5); the dev build runs un-bundled via `swift run`. (The menu-bar label stays an inlined `Text` — no separate view needed.)

---

## M2 — Fast switch + settings + real-time ✅

*Built in two parts: M2a (selectable metric + fast-switch + settings) and M2b (real-time FSEvents + incremental scan). GUI confirmed; 36 tests green.*

1. **Selection model** (`Metrics/MetricSelection.swift`)
   - [x] `Metric {tokens, cost, limit5h, limitWeekly}` + `MetricSelection {provider, metric, period, tokenDefinition}`.
   - [x] Pure rendering: `render(from:)` (abbreviated), `renderExact(from:)` (grouped), `label`, `header`. Cost/limits render `—` until M3/M4.
   - [x] Persistence via `jsonString` / `init?(jsonString:)` — deliberately **not** `RawRepresentable<String>`: the stdlib's `Codable`-for-`RawRepresentable` default shadows the member-wise coding and recurses (`rawValue` → `encode(self)` → `rawValue` → …), a SIGBUS stack overflow that the round-trip test caught.
   - **Deliverable:** ✅ tests — render-by-definition, period switch, labels/headers, cost/limit placeholders, JSON round-trip.
2. **Number formatting** (`Formatting/NumberFormatting.swift`)
   - [x] K/M/B abbreviation + grouped exact (landed in M1, with tests: 999 → "999", 1_500 → "1.5K", 38_214_556 → "38.2M").
   - [x] Currency formatting (`UsageFormat.cost` / `costExact`) — added in M3.
   - [x] Integer-percent formatting (`UsageFormat.percent`) — added in M4a.
3. **Fast-switch dropdown** (`App/MenuContentView.swift`)
   - [x] Quick-switch rows (token periods: Today / This Week / This Month / Last 30 Days) with live per-row values + a checkmark on the active one; one tap updates the selection. (Cost/limit rows join in M3/M4.)
   - [x] Recomputes from the in-memory snapshot on switch — no rescan.
   - **Deliverable:** ✅ flipping rows updates the menu-bar value instantly.
4. **Real-time refresh** (`App/RefreshController.swift`)
   - [x] FSEvents recursive watch on each data root; ~400 ms debounce; triggers `UsageStore.refresh()`. (Limit-snapshot watch is M4.)
   - [x] Optional interval `Timer` for the non-real-time cadences (also advances rolling windows when idle).
   - [x] "Updates" setting: Real-time (default) / 1s / 2s / 5s / 10s / 30s.
   - [x] **Incremental scan pulled forward from M4** (`Scanning/ScanState.swift`, `UsageScanner+Incremental.swift`): re-stat all files, read only new/grown ones (resume from byte offset), accumulate into the deduped map. First pass full; later passes read a few KB — cheap enough to run on every change.
   - **Deliverable:** ✅ a new Claude turn updates the menu bar within the debounce window; refresh is incremental, no main-thread stall.
5. **Settings + persistence** (`App/SettingsView.swift`)
   - [x] `Settings` scene with pickers: token metric, day boundaries (local/UTC), updates cadence.
   - [x] Persisted via **manual `UserDefaults`** (the whole selection as one JSON string; zone + interval as enum raw values) — not `@AppStorage`, which doesn't compose with `@Observable`.
   - **Deliverable:** ✅ settings persist across relaunch.

---

## M3 — Cost ✅

*GUI confirmed; 40 tests green. Cross-checked against an external reference dashboard (below).*

- [x] `CostCalculator` (`Pricing/CostCalculator.swift`): folds the per-model token map → `PricingTable.cost` per model → sum; unpriced models' billable tokens collect into `unknownModelTokens` (flagged, never zeroed into the total). The `Aggregator` bakes per-period `cost` + `unknownModelTokens` into the snapshot.
- [x] **Cost metric**: `MetricSelection` renders `.cost` (abbreviated `$4.8K`, exact `$4,774.94` via `UsageFormat.cost` / `costExact`); the quick-switch gains **Cost — This Month / Today** rows.
- [x] **Per-model breakdown** in the dropdown ("By model" — per-model tokens on a tokens view, per-model `$` on a cost view), largest first; plus an "excludes N tokens from unpriced models" note on cost views.
- [x] **Multi-root**: `ClaudeProvider` scans the Xcode `CodingAssistant` dir **when present** (existence-checked) — included-when-found rather than an `includeXcodeDir` toggle; an opt-out can come later.
- [x] `--scan-once` prints estimated cost per period (a headless cross-check aid).
- **Deliverable:** ✅ Last-30-days cost **$4,774.94** vs the reference dashboard's **$4,419.37** — the ~$355 delta is **fable-5**, which bar-models prices ($10/$50) and the reference doesn't; accounting for that, the figures reconcile. Unknown-model flagging works (`<synthetic>` tokens surfaced).

---

## M4 — Plan limits — M4a ✅ (estimate) · M4b ✅ (official hook)

*M4a (read-only estimate) built & GUI-confirmed. M4b (the status-line hook) built; 73 tests green; `--scan-once` shows `official` with a fresh snapshot, the labeled estimate otherwise.*

### M4a — Estimate (read-only) ✅ (`Limits/`)

- [x] `FiveHourWindower` groups events into 5-hour blocks (start at first activity, last 5h); future timestamps are clamped (`timestamp <= now`).
- [x] `LimitEstimator`: 5-hour = active-block billable ÷ **P90 of historical blocks**; weekly = rolling-7-day billable ÷ **P90 of 7-day rolling sums** (two-pointer, O(n)). Budget order: **custom → P90 → unavailable** — *no plan-multiplier seed* (a token seed can't map to `billableTotal`, which is what's summed). Everything flagged `est`; `LimitStatus{percent, isOfficial, available, basis}` baked into the snapshot by the `Aggregator`.
- [x] `LimitBudgets` carries optional custom budgets (the settings UI for them lands with M4b).
- [x] UI: **Plan limit — 5h / Weekly** quick-switch rows render `~NN%` (`—` when no data); the dropdown shows the basis; the menu-bar value turns **amber past 80% / red past 100%**.
- [x] `--scan-once` prints the limit estimates.
- **Deliverable:** ✅ a labeled estimate renders with the hook off; windower / P90 / rolling-sum / custom-budget / empty tests pass.
- *Deferred beyond M4b:* `PlanLimits`/`Plan` (Pro / Max 5× / 20×) — the official path yields an absolute % directly, so a plan multiplier has no consumer yet; the worthwhile follow-up is calibrating the estimate's fallback budget from observed official readings (`budget ≈ used ÷ official%`).

### M4b — Official path ✅

- [x] `scripts/bar-models-statusline.sh` reads Claude Code's status-line JSON on stdin and writes `{five_hour, seven_day, five_hour_resets_at, seven_day_resets_at, model, ts}` to `~/.claude/bar-models/snapshot.json` **atomically** (temp + `mv`), passing input through to any wrapped prior command. Best-effort and guarded — a missing `jq` (it prepends the common bin paths first) or bad input never breaks the status line.
- [x] `Limits/LimitSource.swift` reads the snapshot when fresh (staleness threshold; also drops a window once its `resets_at` has passed) and converts Claude Code's 0–100 to the `LimitStatus` 0…1 scale. `Aggregator` gained an `official:` argument and uses `official ?? estimate` per window; `UsageStore` reads `LimitSource` inside its detached scan, so a fresh reading renders `42%` (no `~`) and a stale/absent one falls back to the labeled estimate.
- [x] In-app **opt-in** "Enable live limits" (`App/LiveLimits.swift`, Settings → Plan limits) installs the bundled script to `~/.claude/bar-models/` and wraps `statusLine` in `~/.claude/settings.json` with explicit consent — atomic write + one-time `settings.json.bak`, all sibling keys preserved, idempotent, and **disable verifies the hook is still ours** before restoring/removing. The existing FSEvents watch picks up the snapshot dir when present; any IO failure reverts the toggle (à la launch-at-login).
- **Deliverable:** ✅ with the hook on and Claude Code active, the app's 5h/7d % matches `/usage`; `--scan-once` prints `official` with a fresh snapshot and `est · …` otherwise. Covered by `LimitSourceTests`, `OfficialOverrideTests`, `StatusLineConfigTests`, `StatusLineScriptTests`, and `UsageStoreTests`.

### Persisted incremental scan (extends M2's in-memory scan)

- [x] In-memory incremental scan landed in **M2** (real-time needs it).
- [x] Persist the full `ScanState` (per-file cursors **and** the deduped event map) across launches via `Scanning/ScanStateStore.swift` — a versioned, atomic JSON cache at `~/Library/Caches/bar-models/scan-state.json`. The first post-launch scan resumes from saved offsets; a corrupt / version-mismatched / stale cache falls back to a full scan. Shrink/rotate refined with `inode` + birthtime identity on `FileScanState`, so a replaced (or inode-reused) file re-reads from 0; `UsageStore` loads off-main on the first refresh and saves debounced (by value) after each.

---

## M5 — Polish & notarize — code ✅ · notarization pending (Developer ID cert)

*Polish (launch-at-login, empty/first-run state, settings sections) built; 50 tests green. The `.app` bundle + release pipeline are scripted and verified through ad-hoc signing; the notarized `.dmg` needs a Developer ID cert (none installed — see `09-distribution.md`).*

- [x] **Launch-at-login** (`App/LaunchAtLogin.swift`): `SMAppService.mainApp` register/unregister behind a Settings toggle. Best-effort — registration only sticks for a signed, bundled `.app`, so the toggle mirrors the real `status` (a dev `swift run` can't register; logged via `OSLog`, never fatal).
- [x] **Empty/first-run state** (`Aggregation/DataAvailability.swift`): a pure `loading / noSource / empty / ready` classification (tested), fed by a new `UsageStore.hasDataSources` signal computed off-main. The dropdown shows a friendly "No usage data found" (no `~/.claude`) or "No usage recorded yet" (empty folder); the menu-bar label shows `—` instead of `0`; quick-switch rows stay hidden until data exists.
- [x] **Settings polish** (`App/SettingsView.swift`): grouped into General (launch-at-login) / Display (token metric, day boundaries = local/UTC timezone) / Updates (refresh cadence), each with help text.
- [x] **`.app` bundle + release pipeline** (`scripts/package-app.sh`, `scripts/release.sh`, `VERSION`): builds a universal (arm64+x86_64) `LSUIElement` bundle; ad-hoc signs for local use, Developer ID signs (`--options runtime` + `--timestamp`) for release; then DMG (with `/Applications` symlink) → `notarytool submit --wait` → `stapler staple` → `spctl` verify. Verified locally: universal binary, `LSUIElement=true`, `codesign --verify --strict` passes on the ad-hoc bundle.
- [ ] **Notarization** (`scripts/release.sh`): needs a Developer ID Application cert + a stored notarytool profile (the user's Apple Developer account). One command once the cert is installed: `scripts/release.sh --sign "Developer ID Application: NAME (TEAMID)" --notary-profile bar-models-notary`.
- **Deliverable:** code polish ✅ and the pipeline ✅ through signing; the notarized `.dmg` that launches clean on a second Mac is one `scripts/release.sh` run away, blocked only on the cert.

---

## M6 — Additional providers (post-MVP)

- [ ] `Providers/Codex/CodexProvider.swift`, `Providers/Gemini/GeminiProvider.swift` conforming to `UsageProvider`; discover each CLI's data location, record format, and pricing.
- [ ] Add them to `ProviderRegistry`; add provider scope to the menu (per-provider / All).
- **Deliverable:** Codex/Gemini usage shows behind the same UI with no core changes.
