#!/usr/bin/env bash
#
# Assemble a release `bar-models.app` bundle from the SwiftPM executable.
# The app is menu-bar-only (LSUIElement) and un-sandboxed (reads ~/.claude
# directly). See docs/09-distribution.md for the full release pipeline.
#
# Usage:
#   scripts/package-app.sh                 # ad-hoc sign (runs locally)
#   scripts/package-app.sh --sign "Developer ID Application: NAME (TEAMID)"
#
# A Developer ID signature additionally enables Hardened Runtime + a secure
# timestamp (both required for notarization, and for login-item registration).
# BUILD_NUMBER env var overrides CFBundleVersion (default 1).
set -euo pipefail

APP_NAME="bar-models"
BUNDLE_ID="com.bar-models.app"
MIN_MACOS="14.0"

# Sparkle (in-app updates) configuration baked into Info.plist.
#   • SU_FEED_URL — the `latest/download` redirect is stable across releases and
#     always resolves to the newest Release's appcast.xml asset.
#   • SU_PUBLIC_ED_KEY — the base64 EdDSA *public* key. The matching private key
#     lives only in the keychain / the SPARKLE_EDDSA_PRIVATE_KEY CI secret and
#     signs each appcast (see docs/09-distribution.md → "Auto-updates"). Replace
#     the placeholder below with the key `generate_keys` prints (one-time setup).
SU_FEED_URL="https://github.com/awinogradov/bar-models/releases/latest/download/appcast.xml"
SU_PUBLIC_ED_KEY="REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"

SIGN_IDENTITY="-" # ad-hoc by default
while [ $# -gt 0 ]; do
    case "$1" in
        --sign) SIGN_IDENTITY="${2:?--sign needs an identity}"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(cat VERSION 2>/dev/null || echo 0.0.0)"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCH_FLAGS=(--arch arm64 --arch x86_64) # universal, so the DMG runs on any Mac

echo "› building universal release binary ($VERSION build $BUILD_NUMBER)…"
swift build -c release "${ARCH_FLAGS[@]}"
BIN_PATH="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

APP="build/${APP_NAME}.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$BIN_PATH/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

# Bundle the status-line hook so the in-app "Enable live limits" opt-in can install it.
cp "$ROOT/scripts/bar-models-statusline.sh" "$CONTENTS/Resources/bar-models-statusline.sh"
chmod 0755 "$CONTENTS/Resources/bar-models-statusline.sh"

# Embed Sparkle.framework. SwiftPM links it but does not assemble an .app, so we
# copy the macOS slice out of the binary artifact's xcframework and add the loader
# rpath the bundled executable needs (`swift build`'s rpath points into .build).
SPARKLE_FW="$(find "$ROOT/.build/artifacts" -type d -path '*Sparkle.xcframework/macos-*/Sparkle.framework' -print -quit)"
if [ -z "$SPARKLE_FW" ]; then
    echo "Sparkle.framework not found under .build/artifacts — run 'swift package resolve' first" >&2
    exit 1
fi
ditto "$SPARKLE_FW" "$CONTENTS/Frameworks/Sparkle.framework" # ditto preserves the framework's symlinks
# Add the loader rpath unless `swift build` already emitted it (it usually does);
# a duplicate LC_RPATH is harmless but avoidable, and the guard keeps us correct
# if a future toolchain stops adding it.
if ! otool -l "$CONTENTS/MacOS/$APP_NAME" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/$APP_NAME"
fi

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Bar Models</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>bar-models</string>
    <key>SUFeedURL</key>
    <string>${SU_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SU_PUBLIC_ED_KEY}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
EOF

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "› ad-hoc signing (local use; not distributable)…"
    SIGN_ARGS=(--force --sign -)
else
    echo "› signing with Developer ID (hardened runtime + timestamp)…"
    SIGN_ARGS=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
fi

# Sign nested code inside-out: every helper inside Sparkle.framework first, then
# the framework, then the outer app. `--deep` is intentionally avoided (it mis-signs
# nested bundles and is deprecated); the framework + helpers ship with their own
# signatures, so each must be re-signed with our identity for notarization to pass.
FW="$CONTENTS/Frameworks/Sparkle.framework"
FW_V="$FW/Versions/B"
for nested in \
    "$FW_V/XPCServices/Downloader.xpc" \
    "$FW_V/XPCServices/Installer.xpc" \
    "$FW_V/Updater.app" \
    "$FW_V/Autoupdate"; do
    [ -e "$nested" ] && codesign "${SIGN_ARGS[@]}" "$nested"
done
codesign "${SIGN_ARGS[@]}" "$FW"
codesign "${SIGN_ARGS[@]}" "$APP"

echo "✓ $APP"
