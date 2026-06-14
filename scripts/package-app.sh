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
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_PATH/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

# Bundle the status-line hook so the in-app "Enable live limits" opt-in can install it.
cp "$ROOT/scripts/bar-models-statusline.sh" "$CONTENTS/Resources/bar-models-statusline.sh"
chmod 0755 "$CONTENTS/Resources/bar-models-statusline.sh"

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
</dict>
</plist>
EOF

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "› ad-hoc signing (local use; not distributable)…"
    codesign --force --sign - "$APP"
else
    echo "› signing with Developer ID (hardened runtime + timestamp)…"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

echo "✓ $APP"
