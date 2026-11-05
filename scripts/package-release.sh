#!/usr/bin/env bash
# Builds, signs with Developer ID, notarizes and staples Kex.app, zips it into dist/, and writes the Sparkle
# appcast and the Homebrew cask.
# Usage: scripts/package-release.sh 0.3
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: scripts/package-release.sh X.Y}"
version="${version#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+$ ]] || { echo 'Expected version X.Y' >&2; exit 1; }
profile="${NOTARYTOOL_PROFILE:-TunaNotary}"
identity="${DEVELOPER_ID_APPLICATION:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"
[[ -n "$identity" ]] || { echo 'No Developer ID Application identity; set DEVELOPER_ID_APPLICATION' >&2; exit 1; }
build="$(( $(git rev-list --count HEAD) + 100 ))"

echo "==> Building and signing Kex.app $version ($build) with $identity"
VERSION="$version" BUILD="$build" IDENTITY="$identity" SIGN_FLAGS="--options runtime --timestamp" scripts/bundle.sh
codesign --verify --strict --verbose=1 build/Kex.app

mkdir -p dist
rm -f dist/Kex.app.zip dist/signature.txt dist/appcast.xml dist/kex.rb
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==> Notarizing with profile $profile"
ditto -c -k --sequesterRsrc --keepParent build/Kex.app "$tmp/kex.zip"
xcrun notarytool submit "$tmp/kex.zip" --keychain-profile "$profile" --wait
xcrun stapler staple build/Kex.app
spctl --assess --type execute --verbose=1 build/Kex.app

ditto -c -k --sequesterRsrc --keepParent build/Kex.app dist/Kex.app.zip

echo "==> Signing the update and writing the appcast and the cask"
sign_update="$(find .build/artifacts -path '*/Sparkle/bin/sign_update' | head -1)"
"$sign_update" --account com.brnbw.kex -p dist/Kex.app.zip > dist/signature.txt
python3 scripts/appcast.py "$version"
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$(shasum -a 256 dist/Kex.app.zip | cut -d' ' -f1)/" scripts/kex.rb.template > dist/kex.rb
echo "==> dist/Kex.app.zip ($(du -h dist/Kex.app.zip | cut -f1)), version $version build $build"
