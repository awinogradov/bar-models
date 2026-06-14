#!/usr/bin/env bash
#
# Build, sign, package, notarize, staple, and verify a distributable DMG.
# This is the M5 release pipeline from docs/distribution.md.
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
while [ $# -gt 0 ]; do
    case "$1" in
        --sign) SIGN_IDENTITY="${2:?}"; shift 2 ;;
        --notary-profile) NOTARY_PROFILE="${2:?}"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$SIGN_IDENTITY" ] || [ -z "$NOTARY_PROFILE" ]; then
    echo "usage: $0 --sign \"Developer ID Application: NAME (TEAMID)\" --notary-profile PROFILE" >&2
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

# 5. Verify the signature and Gatekeeper acceptance.
echo "› verifying…"
codesign --verify --strict --verbose=2 "$APP"
spctl -a -t open --context context:primary-signature -v "$DMG"

echo "✓ notarized DMG ready: $DMG"
