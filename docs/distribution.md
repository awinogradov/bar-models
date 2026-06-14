# Distribution

Ship as a **notarized `.dmg`** anyone can download and run. The app is **un-sandboxed** (so it reads `~/.claude` directly with no security-scoped bookmarks) but uses the **Hardened Runtime** (required for notarization).

## Prerequisite

A **Developer ID Application** certificate must be installed in the login keychain (Apple Developer Program enrollment required). Check:

```sh
security find-identity -v -p codesigning
```

If this lists no valid identity, signing/notarization cannot proceed — install the cert first. (On the dev machine at planning time: 0 identities.)

## Entitlements

- App Sandbox: **OFF** (no `com.apple.security.app-sandbox`). Un-sandboxed home-dir reads need no file entitlements.
- Hardened Runtime: **ON** (build setting `ENABLE_HARDENED_RUNTIME = YES`). For plain file reads, no hardened-runtime exception keys are needed.

## Release steps

```sh
# 1. Sign the app (hardened runtime, secure timestamp)
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <Name> (<TEAMID>)" \
  build/inline-usage.app
# Sign nested code (frameworks/bundles) inner-first if any; avoid --deep on complex bundles.

# 2. Build the DMG (the signed .app + an /Applications symlink)
hdiutil create -volname "inline-usage" -srcfolder build/inline-usage.app \
  -ov -format UDZO dist/inline-usage.dmg
# (or use create-dmg for a nicer layout)

# 3. Notarize (store creds once: notarytool store-credentials)
xcrun notarytool submit dist/inline-usage.dmg \
  --keychain-profile "inline-usage-notary" --wait

# 4. Staple the ticket (offline Gatekeeper validation)
xcrun stapler staple dist/inline-usage.dmg

# 5. Verify
spctl -a -t open --context context:primary-signature -v dist/inline-usage.dmg
codesign --verify --strict --verbose=2 build/inline-usage.app
```

## Notes

- Signing/notarization touch the keychain and network — they run in a release script, not in CI sandboxes without the cert + an app-specific password / stored profile.
- The app target sets `LSUIElement = YES` (menu-bar only, no Dock icon).
- Keep a release checklist: bump version, archive, sign, dmg, notarize, staple, verify, smoke-test on a clean Mac.
