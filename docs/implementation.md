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

## M1 — Skeleton + one real number

**Goal:** a correct, deduped "Tokens · This Month (input+output)" in the menu bar, off-main, on the real ~521 MB tree.

1. **`JSONLReader`** (`Scanning/JSONLReader.swift`)
   - [ ] Stream a file via `FileHandle`, read fixed chunks (~256 KB), split on `\n`, yield complete lines as `Data`; retain the trailing partial line (don't yield it).
   - [ ] Support `seek(toOffset:)` to resume from a byte offset.
   - **Deliverable:** reads a multi-line fixture without loading the whole file; unit test on a fixture with a partial last line.
2. **Claude record decoding** (`Providers/Claude/ClaudeRecord.swift` + flesh out `ClaudeProvider.parse`)
   - [ ] Lenient `Decodable` mirror: every field optional; `message.usage` decodes only `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`.
   - [ ] `parse(line:)`: keep `type == "assistant"` with a non-empty `message.id` and non-zero tokens; parse `timestamp` (cached POSIX `DateFormatter`, GMT, `yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX` with a no-fractional fallback); tag `provider = .claude`; return `nil` on anything unparseable.
   - **Deliverable:** tests over fixtures — dup `message.id` (identical tokens), an `iterations` array (ignored), all-zero record (skipped), `<synthetic>`/missing-id (skipped), corrupt line (skipped).
3. **`UsageScanner`** (`Scanning/UsageScanner.swift`)
   - [ ] Enumerate `*.jsonl` under each `provider.dataRoots()` (`FileManager.enumerator`, prefetch mtime+size).
   - [ ] Parse all lines → global `[id: UsageEvent]` dedup map → `[UsageEvent]`.
   - [ ] (Incremental scan/`FileScanState` deferred to M4 — M1 may do a full cold scan.)
   - **Deliverable:** scanning the real tree returns a plausible deduped event count; runs off-main without error.
4. **Aggregation** (`Aggregation/PeriodBucketer.swift`, `Aggregator.swift`)
   - [ ] `Period` enum {today, thisWeek, thisMonth, rolling7, rolling30}; bucket by **local** calendar day (default), `Calendar.current`.
   - [ ] `Aggregator`: single pass → `TokenCounts` per (period, model).
   - **Deliverable:** tests for local-vs-UTC month edges and week start (`firstWeekday`).
5. **`UsageStore`** (`Aggregation/UsageStore.swift`)
   - [ ] `@MainActor @Observable`; holds the aggregate snapshot; `refresh()` runs the scan off-main and assigns the snapshot on the main actor; single-flight.
   - **Deliverable:** exposes "tokens this month (input+output)" as a computed value.
6. **App skeleton** (`App/` in an Xcode app target, LSUIElement)
   - [ ] `MenuBarExtra { MenuContentView } label: { MenuBarLabelView }`, `.menuBarExtraStyle(.window)`.
   - [ ] Label shows the formatted value (K/M/B, monospaced digits); dropdown shows exact value + Quit; "Loading…" until first scan completes.
   - **Deliverable:** launches, shows a correct deduped monthly number without stalling the menu bar.

---

## M2 — Fast switch + settings + real-time

1. **Selection model** (`Metrics/`)
   - [ ] `Metric {tokens, cost, limit5h, limitWeekly}`, `TokenDefinition` (exists), `MetricSelection {provider, metric, period, tokenDefinition}` + `renderTitle(snapshot) -> String` + `renderHeader`.
   - **Deliverable:** unit tests for `renderTitle` across combos.
2. **Number formatting** (`Formatting/NumberFormatting.swift`)
   - [ ] K/M/B abbreviation (1 decimal), currency, integer percent.
   - **Deliverable:** formatting tests (999 → "999", 1_250 → "1.2K", 38_214_556 → "38.2M").
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
