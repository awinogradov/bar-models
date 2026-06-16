# Distribution

Ship as a **notarized `.dmg`** anyone can download and run. The app is **un-sandboxed** (so it reads `~/.claude` directly with no security-scoped bookmarks) but uses the **Hardened Runtime** (required for notarization).

## Prerequisites

Two one-time credentials must exist on the build machine before the pipeline runs. Both are Apple-account steps — no code, and nothing CI can do without them.

### 1. Developer ID Application certificate

Requires an **Apple Developer Program** membership; on an Organization team only the **Account Holder** can create a Developer ID cert. Easiest path with full Xcode installed:

1. Xcode → **Settings** (⌘,) → **Accounts** → add the Apple ID and select the team → **Manage Certificates…**
2. Click **+** → **Developer ID Application**. Xcode mints the cert *and* its private key straight into the **login** keychain.

Website alternative: create a CSR via **Keychain Access → Certificate Assistant → Request a Certificate…**, upload it at [developer.apple.com](https://developer.apple.com/account) → Certificates → **Developer ID Application**, then double-click the downloaded `.cer`. If the cert already lives on another Mac, export a **`.p12` (with private key)** there and import it here.

Confirm it landed:

```sh
security find-identity -v -p codesigning
# 1) <SHA>  "Developer ID Application: <Name> (<TEAMID>)"   ← this quoted string is the --sign value
```

If `codesign` later rejects the chain as untrusted, install the *Developer ID Certification Authority* intermediate from <https://www.apple.com/certificateauthority/>.

### 2. notarytool keychain profile

`notarytool` authenticates with your Apple ID plus an **app-specific password** (generate at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords — works alongside 2FA). Store it once under the profile name `release.sh` expects:

```sh
xcrun notarytool store-credentials bar-models-notary \
  --apple-id you@example.com --team-id <TEAMID> --password xxxx-xxxx-xxxx-xxxx
```

## Entitlements

- App Sandbox: **OFF** (no `com.apple.security.app-sandbox`). Un-sandboxed home-dir reads need no file entitlements.
- Hardened Runtime: **ON** (build setting `ENABLE_HARDENED_RUNTIME = YES`). For plain file reads, no hardened-runtime exception keys are needed.

## Release

With both prerequisites in place, `scripts/release.sh` runs the whole chain — build → sign → DMG → notarize → staple → verify — and emits `dist/bar-models.dmg`:

```sh
scripts/release.sh \
  --sign "Developer ID Application: <Name> (<TEAMID>)" \
  --notary-profile bar-models-notary
```

The individual steps it automates, for reference:

```sh
# 1. Sign the app (hardened runtime, secure timestamp)
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <Name> (<TEAMID>)" \
  build/bar-models.app
# Sign nested code (frameworks/bundles) inner-first if any; avoid --deep on complex bundles.

# 2. Build the DMG (the signed .app + an /Applications symlink)
hdiutil create -volname "bar-models" -srcfolder build/bar-models.app \
  -ov -format UDZO dist/bar-models.dmg
# (or use create-dmg for a nicer layout)

# 3. Notarize (store creds once: notarytool store-credentials)
xcrun notarytool submit dist/bar-models.dmg \
  --keychain-profile "bar-models-notary" --wait

# 4. Staple the ticket (offline Gatekeeper validation)
xcrun stapler staple dist/bar-models.dmg

# 5. Verify
spctl -a -t open --context context:primary-signature -v dist/bar-models.dmg
codesign --verify --strict --verbose=2 build/bar-models.app
```

## Releasing from CI

The [`Release` workflow](../.github/workflows/release.yml) reproduces the whole `scripts/release.sh` chain on a `macos-latest` GitHub Actions runner, so a release can be cut from a tag without anyone holding the signing identity locally. It triggers on a `v*` tag push (and can be run manually via **workflow_dispatch**), imports the Developer ID certificate into an ephemeral keychain, recreates the `bar-models-notary` notarytool profile from secrets, runs `scripts/release.sh` unchanged, then uploads `dist/bar-models.dmg` as a build artifact and **creates (publishes) the GitHub Release for the tag with the DMG attached as a release asset**. A `workflow_dispatch` run (no tag) produces only the build artifact — it creates no Release. The job fails rather than publishing a Release without the DMG if the file is ever missing.

The runner version (`CFBundleShortVersionString`) still comes from the `VERSION` file, so the workflow asserts that the pushed tag matches `VERSION` (e.g. tag `v0.1.0` requires `VERSION` = `0.1.0`) and fails fast on a mismatch. `CFBundleVersion` is set to the workflow run number.

### Required repository secrets

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERT_P12_BASE64` | base64 of the exported `.p12` (Developer ID Application cert + private key) |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` export password |
| `KEYCHAIN_PASSWORD` | password for the ephemeral CI keychain (any random string) |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | app-specific password for that Apple ID |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Sparkle EdDSA private key that signs the appcast (see [Auto-updates](#auto-updates-sparkle)) |

### How to obtain each secret

Do this once, on the Mac that already holds the working signing setup (see [Prerequisites](#prerequisites)).

1. **`DEVELOPER_ID_CERT_P12_BASE64`** + **`DEVELOPER_ID_CERT_PASSWORD`** — export the cert *with its private key*:
   - Open **Keychain Access** → **login** keychain → **My Certificates**, find `Developer ID Application: <Name> (<TEAMID>)` (confirm it exists: `security find-identity -v -p codesigning`).
   - Right-click it → **Export "Developer ID Application…"** → save as `cert.p12`. The password you set at the prompt is **`DEVELOPER_ID_CERT_PASSWORD`**. (Exporting the *certificate* row, not the bare key, includes both cert + private key.)
   - Base64-encode it for the secret value: `base64 -i cert.p12 | pbcopy` → that is **`DEVELOPER_ID_CERT_P12_BASE64`**.
   - Delete the local copy afterward: `rm cert.p12`.

2. **`KEYCHAIN_PASSWORD`** — not an Apple value; it only protects the throwaway CI keychain. Invent a random one: `openssl rand -base64 24`.

3. **`APPLE_ID`** — the Apple ID **email** enrolled in the Apple Developer Program (the same one used for `notarytool store-credentials` above).

4. **`APPLE_TEAM_ID`** — the 10-character Team ID. It is the value in parentheses from `security find-identity -v -p codesigning` (`… (TEAMID)`), or at [developer.apple.com/account](https://developer.apple.com/account) → **Membership details** → Team ID.

5. **`APPLE_APP_SPECIFIC_PASSWORD`** — generate at [account.apple.com](https://account.apple.com) → **Sign-In and Security** → **App-Specific Passwords** → **+** (label it e.g. `bar-models-notary`). This is the same credential used for `notarytool store-credentials` above; it works alongside 2FA and can be revoked independently.

6. **`SPARKLE_EDDSA_PRIVATE_KEY`** — the Sparkle update-signing key. See [Auto-updates](#auto-updates-sparkle) for how to generate it; the secret value is the exported private-key file's contents.

Add them under **Settings → Secrets and variables → Actions → New repository secret**, or via the `gh` CLI:

```sh
gh secret set DEVELOPER_ID_CERT_P12_BASE64 < <(base64 -i cert.p12)
gh secret set DEVELOPER_ID_CERT_PASSWORD          # prompts for the value
gh secret set KEYCHAIN_PASSWORD
gh secret set APPLE_ID
gh secret set APPLE_TEAM_ID
gh secret set APPLE_APP_SPECIFIC_PASSWORD
```

## Auto-updates (Sparkle)

The app updates itself in place via [Sparkle](https://sparkle-project.org). An installed copy polls an **appcast** (an RSS feed of releases), and when a newer build is signed and published it downloads the DMG, verifies it, swaps the app, and relaunches — no manual re-download. Sparkle is a dependency of the SwiftUI app target only; `UsageCore` stays third-party-free.

```
RELEASE (git tag vX.Y.Z → CI)                 CLIENT (installed app, Sparkle)
  build ─▶ embed+sign Sparkle.framework         launch / "Check for Updates…" / schedule
  package .app ─▶ DMG ─▶ notarize ─▶ staple         │
        │                                           ▼
        ▼                                   GET …/releases/latest/download/appcast.xml
  generate_appcast (EdDSA-sign DMG)                 │ newer build? verify EdDSA + notarization
        │                                           ▼
  upload to Release:  bar-models.dmg + appcast.xml  download DMG ─▶ swap app ─▶ relaunch
```

### Trust model

- **EdDSA (ed25519):** Sparkle independently signs every update with a private key you generate once. The matching **public** key is baked into the app's `Info.plist` (`SUPublicEDKey`), so a client only installs a DMG whose appcast entry carries a valid signature. This is *in addition to* Developer ID + notarization.
- **Feed URL:** `SUFeedURL` is `https://github.com/awinogradov/bar-models/releases/latest/download/appcast.xml` — GitHub's `latest/download` redirect always resolves to the newest Release's `appcast.xml` asset, so the feed URL never changes between releases. Served over HTTPS, as Sparkle requires.

### One-time key setup

The EdDSA keypair is generated once and reused for every release (like the Developer ID cert). **Losing the private key means clients can no longer be issued updates** — back it up.

1. Generate the keypair (stores the private key in your login keychain, prints the public key):

   ```sh
   .build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

   Run `swift package resolve` first if `.build/artifacts` is absent.

2. Copy the printed base64 **public** key into `scripts/package-app.sh` — replace the `SU_PUBLIC_ED_KEY="REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"` placeholder. This is safe to commit.

3. Export the **private** key for CI and store it as the `SPARKLE_EDDSA_PRIVATE_KEY` repository secret, then delete the local copy:

   ```sh
   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private.key
   gh secret set SPARKLE_EDDSA_PRIVATE_KEY < sparkle_private.key
   rm sparkle_private.key
   ```

   Also keep a copy in a password manager. On the dev machine, local `scripts/release.sh` runs read the key straight from the keychain, so `--ed-key-file` is only needed in CI.

### How a release produces the appcast

`scripts/release.sh` runs `generate_appcast` after notarize + staple: it reads the version from inside the DMG, EdDSA-signs the enclosure, and writes `dist/appcast.xml` with the enclosure URL pointed at that tag's Release download dir (`--appcast-url-prefix`). The CI workflow attaches **both** `bar-models.dmg` and `appcast.xml` to the Release and fails if either is missing. Each release publishes a single-item appcast (just the latest build) — sufficient for "is there something newer" checks without retaining every historical archive.

### First-release caveat

The pre-Sparkle `0.1.0` build has no updater, so it cannot auto-update *to* the first Sparkle-enabled release — that one upgrade is a manual DMG install. Every release after it updates in place. Call this out in the release notes for the first Sparkle build.

## Notes

- Signing/notarization touch the keychain and network. They run locally via `scripts/release.sh`, or in CI via the [`Release` workflow](#releasing-from-ci), which recreates the same keychain + notarytool profile on a hosted runner from repository secrets.
- The first `codesign` with a freshly created identity may raise a one-time *"codesign wants to access the keychain"* dialog — click **Always Allow** so it never blocks again.
- The app target sets `LSUIElement = YES` (menu-bar only, no Dock icon).
- Keep a release checklist: bump version, archive, sign, dmg, notarize, staple, verify, smoke-test on a clean Mac.
- Validated end-to-end on a fresh enrollment: `scripts/release.sh` produced `dist/bar-models.dmg` with notary status **Accepted**, stapled, and `spctl` → *accepted, source=Notarized Developer ID*. The clean-second-Mac launch is the final manual acceptance check.
