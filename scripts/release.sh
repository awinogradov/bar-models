#!/usr/bin/env bash
#
# Build, sign, package, notarize, staple, and verify a distributable DMG.
# This is the M5 release pipeline from docs/09-distribution.md.
#
# Prerequisites (one-time):
#   • a "Developer ID Application" certificate in the login keychain
#       security find-identity -v -p codesigning
#   • a stored notarytool keychain profile
#       xcrun notarytool store-credentials bar-models-notary \
#         --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
#
# Usage:
#   scripts/release.sh --sign "Developer ID Application: NAME (TEAMID)" \
#                      --notary-profile bar-models-notary
set -euo pipefail

APP_NAME="bar-models"
SIGN_IDENTITY=""
NOTARY_PROFILE=""
ED_KEY_FILE=""        # optional: EdDSA private key file (CI); default reads the keychain
APPCAST_URL_PREFIX="" # optional: absolute enclosure URL base, e.g. the GitHub Release download dir
while [ $# -gt 0 ]; do
    case "$1" in
        --sign) SIGN_IDENTITY="${2:?}"; shift 2 ;;
        --notary-profile) NOTARY_PROFILE="${2:?}"; shift 2 ;;
        --ed-key-file) ED_KEY_FILE="${2:?}"; shift 2 ;;
        --appcast-url-prefix) APPCAST_URL_PREFIX="${2:?}"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$SIGN_IDENTITY" ] || [ -z "$NOTARY_PROFILE" ]; then
    echo "usage: $0 --sign \"Developer ID Application: NAME (TEAMID)\" --notary-profile PROFILE" >&2
    echo "       [--ed-key-file PATH] [--appcast-url-prefix URL]" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 1. Build + sign the .app (hardened runtime + timestamp via --sign).
scripts/package-app.sh --sign "$SIGN_IDENTITY"

APP="build/${APP_NAME}.app"
DMG="dist/${APP_NAME}.dmg"
mkdir -p dist
rm -f "$DMG"

# 2. DMG with an /Applications symlink for drag-to-install. Stage in TMPDIR
#    (not /Volumes — recent macOS blocks /Volumes writes without Full Disk Access).
echo "› building DMG…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

# 3. Sign the DMG container too.
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

# 4. Notarize and staple the ticket for offline Gatekeeper checks.
echo "› notarizing (this uploads to Apple and waits)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# 5. Verify the signature and Gatekeeper acceptance. --deep so the embedded
#    Sparkle.framework and its nested helpers are validated too, not just the app.
echo "› verifying…"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -t open --context context:primary-signature -v "$DMG"

# 6. Generate the EdDSA-signed appcast that Sparkle clients poll. generate_appcast
#    reads the version from inside the DMG and signs the enclosure; the private key
#    comes from --ed-key-file (CI) or the local keychain (a one-time `generate_keys`
#    on the dev machine — see docs/09-distribution.md → "Auto-updates").
echo "› generating appcast…"
GENERATE_APPCAST="$(find "$ROOT/.build/artifacts" -type f -path '*Sparkle*/bin/generate_appcast' -print -quit)"
if [ -z "$GENERATE_APPCAST" ]; then
    echo "generate_appcast not found under .build/artifacts — run 'swift package resolve' first" >&2
    exit 1
fi
ARCHIVES="$(mktemp -d)"
cp "$DMG" "$ARCHIVES/"
GA_ARGS=("$ARCHIVES")
[ -n "$ED_KEY_FILE" ] && GA_ARGS+=(--ed-key-file "$ED_KEY_FILE")
[ -n "$APPCAST_URL_PREFIX" ] && GA_ARGS+=(--download-url-prefix "$APPCAST_URL_PREFIX")
"$GENERATE_APPCAST" "${GA_ARGS[@]}"
cp "$ARCHIVES/appcast.xml" "dist/appcast.xml"
rm -rf "$ARCHIVES"

echo "✓ notarized DMG ready: $DMG"
echo "✓ appcast ready: dist/appcast.xml"
