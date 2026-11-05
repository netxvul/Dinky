#!/usr/bin/env bash
# Builds build/Kex.app and signs it with a stable identity, so the Accessibility grant survives rebuilds.
# Usage: scripts/bundle.sh [--debug]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0}"
BUILD="${BUILD:-1}"
IDENTITY="${IDENTITY:-Apple Development: Mikkel Malmberg (VAW8MWER4W)}"
SIGN_FLAGS="${SIGN_FLAGS:-}"  # release packaging adds --options runtime --timestamp
CONFIG=release
[[ "${1:-}" == "--debug" ]] && CONFIG=debug

swift build -c "$CONFIG"

APP=build/Kex.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c "$CONFIG" --show-bin-path)/kex" "$APP/Contents/MacOS/kex"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD" "$APP/Contents/Info.plist"

# The app icon: Resources/Kex.icon (Icon Composer) compiled into Assets.car and an icns fallback.
ICON_OUT="$(mktemp -d)"
xcrun actool "$PWD/Resources/Kex.icon" --compile "$ICON_OUT" --platform macosx --minimum-deployment-target 15.0 \
  --app-icon Kex --include-all-app-icons --output-partial-info-plist "$ICON_OUT/partial.plist" >/dev/null
mkdir -p "$APP/Contents/Resources"
cp "$ICON_OUT/Assets.car" "$ICON_OUT/Kex.icns" "$APP/Contents/Resources/"
plutil -replace CFBundleIconFile -string Kex "$APP/Contents/Info.plist"
plutil -replace CFBundleIconName -string Kex "$APP/Contents/Info.plist"
rm -rf "$ICON_OUT"

# Sparkle.framework from the resolved SwiftPM artifact; the linker rpath finds it here.
SPARKLE_SRC="$(find .build/artifacts -maxdepth 6 -path '*macos-arm64_x86_64/Sparkle.framework' | head -1)"
[[ -n "$SPARKLE_SRC" ]] || { echo 'Sparkle.framework not found in .build/artifacts' >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_SRC" "$APP/Contents/Frameworks/Sparkle.framework"

# Sign inside out: Sparkle's helpers, the framework, then the app.
sign() { codesign --force $SIGN_FLAGS --sign "$IDENTITY" "$1"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for item in XPCServices/Downloader.xpc XPCServices/Installer.xpc Updater.app Autoupdate Sparkle; do
  sign "$SPARKLE/Versions/Current/$item"
done
sign "$SPARKLE"
sign "$APP"
echo "built $APP ($CONFIG, $VERSION build $BUILD)"
