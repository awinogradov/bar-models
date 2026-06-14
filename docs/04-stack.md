# Stack

## Language & platform

- **Swift 6** (strict concurrency), **SwiftUI**, deployment target **macOS 14+**.
- Verified host toolchain: Swift 6.3.2 / Xcode 26.5 / macOS 26.

## Why these choices

- **SwiftUI `MenuBarExtra`** (macOS 13+) is the idiomatic, lightest way to put a configurable value in the menu bar with a rich popover. `.menuBarExtraStyle(.window)` gives a real SwiftUI dropdown.
- **macOS 14+** unlocks `@Observable` (Observation) and `SMAppService` with no shims.
- **Zero third-party dependencies.** Settings use SwiftUI's built-in `@AppStorage`/`UserDefaults` (enums are `String, RawRepresentable`; the composite selection serializes to a small JSON string). Launch-at-login uses `SMAppService`. Result: smaller bundle, no SPM resolution, frictionless notarization.

## Project shape

- **`UsageCore`** — SPM library, no UI imports, unit-tested with **Swift Testing** (`import Testing`, `@Test`/`#expect`). Built/tested from the CLI (`swift build` / `swift test`).
- **App** — Xcode app target (SwiftUI), depends on `UsageCore`, `LSUIElement = YES` (menu-bar only, no Dock icon).

## Key system APIs

- **FSEvents** (`FSEventStreamCreate`) — recursive, coalesced directory watching for real-time refresh. (Not per-file `DispatchSource`: the Claude tree has ~1,500 dirs.)
- **`FileHandle`** — streaming line reads + `seek(toOffset:)` for incremental scanning (the tree is ~521 MB).
- **`Calendar`/`DateComponents`** — local-day period bucketing (UTC toggle available).
- **`SMAppService.mainApp`** — launch-at-login.
- **`@MainActor @Observable`** — the store the SwiftUI views bind to; scanning is off-main with `Sendable` value-type results.

## Distribution

Un-sandboxed (reads `~/.claude` directly), **Hardened Runtime on**, Developer ID signed, notarized `.dmg`. See `09-distribution.md`.

## Non-choices (considered, rejected)

- **Electron/Tauri** — far too heavy for one menu-bar value.
- **Python/rumps** — fast to prototype, but runtime bundling and notarizing a `.app` is awkward.
- **App Store / sandbox** — would force a security-scoped-bookmark grant to read `~/.claude`; a notarized `.dmg` keeps home-dir access simple.
- **`Defaults` package** — `@AppStorage` covers the tiny settings surface natively.
