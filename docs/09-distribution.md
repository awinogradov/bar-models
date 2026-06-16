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

## Notes

- Signing/notarization touch the keychain and network — they run in a release script, not in CI sandboxes without the cert + an app-specific password / stored profile.
- The first `codesign` with a freshly created identity may raise a one-time *"codesign wants to access the keychain"* dialog — click **Always Allow** so it never blocks again.
- The app target sets `LSUIElement = YES` (menu-bar only, no Dock icon).
- Keep a release checklist: bump version, archive, sign, dmg, notarize, staple, verify, smoke-test on a clean Mac.
- Validated end-to-end on a fresh enrollment: `scripts/release.sh` produced `dist/bar-models.dmg` with notary status **Accepted**, stapled, and `spctl` → *accepted, source=Notarized Developer ID*. The clean-second-Mac launch is the final manual acceptance check.
