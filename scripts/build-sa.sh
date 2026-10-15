#!/usr/bin/env bash
# Builds dinky's Dock scripting addition and injects it, so dinky can move and transform other apps' windows
# through Dock's privileged WindowServer connection (what dinky's own connection cannot do; see
# Sources/DinkyPrivate/osax). Requires: SIP Filesystem Protections + Debugging Restrictions disabled, the
# -arm64e_preview_abi boot-arg, and root for the install + injection. Re-run after a Dock restart or reboot.
#
# The injector (osax/loader.m) is derived from yabai's src/osax/loader.m (MIT, © Åsmund Vikane).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
O="$REPO/Sources/DinkyPrivate/osax"
OSAX="$REPO/build/dinky.osax"
INSTALLED="/Library/ScriptingAdditions/dinky.osax"
VER="0.1.0"

if [ ! -f "$O/loader.m" ]; then
    echo "missing $O/loader.m — copy yabai's src/osax/loader.m here and change yabai.osax -> dinky.osax" >&2
    exit 1
fi

echo "compiling payload + loader (arm64e)..."
xcrun clang "$O/payload.m" -I"$O" -shared -fPIC -O2 -mmacosx-version-min=12.0 -arch arm64e \
    -o "$REPO/build/sa-payload" -F/System/Library/PrivateFrameworks -framework SkyLight -framework Cocoa
xcrun clang "$O/loader.m" -I"$O" -O2 -mmacosx-version-min=12.0 -arch arm64e \
    -o "$REPO/build/sa-loader" -framework Cocoa

echo "assembling $OSAX ..."
rm -rf "$OSAX"
mkdir -p "$OSAX/Contents/MacOS" "$OSAX/Contents/Resources/payload.bundle/Contents/MacOS"
cat > "$OSAX/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>loader</string>
<key>CFBundleIdentifier</key><string>app.dinky.dinky-osax</string>
<key>CFBundleName</key><string>dinky</string>
<key>CFBundlePackageType</key><string>osax</string>
<key>CFBundleShortVersionString</key><string>$VER</string>
<key>CFBundleVersion</key><string>$VER</string>
<key>OSAXHandlers</key><dict/></dict></plist>
PLIST
cat > "$OSAX/Contents/Resources/payload.bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>payload</string>
<key>CFBundleIdentifier</key><string>app.dinky.dinky-sa</string>
<key>CFBundleName</key><string>payload</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleShortVersionString</key><string>$VER</string>
<key>CFBundleVersion</key><string>$VER</string>
<key>NSPrincipalClass</key><string></string></dict></plist>
PLIST
cp "$REPO/build/sa-loader" "$OSAX/Contents/MacOS/loader"
cp "$REPO/build/sa-payload" "$OSAX/Contents/Resources/payload.bundle/Contents/MacOS/payload"
chmod +x "$OSAX/Contents/MacOS/loader" "$OSAX/Contents/Resources/payload.bundle/Contents/MacOS/payload"
codesign -f -s - "$OSAX/Contents/MacOS/loader"
codesign -f -s - "$OSAX/Contents/Resources/payload.bundle/Contents/MacOS/payload"

echo "installing to $INSTALLED and injecting Dock (needs root)..."
sudo rm -rf "$INSTALLED"
sudo cp -R "$OSAX" "$INSTALLED"
sudo "$INSTALLED/Contents/MacOS/loader"

sleep 1
if [ -S "/tmp/dinky-sa_$USER.socket" ]; then
    echo "OK: scripting addition loaded (/tmp/dinky-sa_$USER.socket)"
else
    echo "socket missing — injection may have failed; check Console for [dinky-sa]" >&2
    exit 1
fi
