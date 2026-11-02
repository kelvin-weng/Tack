#!/bin/zsh
# Builds everything a GitHub Release needs into dist/v<version>/: the DMG and the signed Sparkle appcast.xml.
# Before running: raise MARKETING_VERSION and CURRENT_PROJECT_VERSION (Sparkle compares the latter). To include
# release notes, put them in dist/v<version>/Tack-<version>.md first. Signing needs the Sparkle key in the Keychain.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/make-dmg.sh"
cd "$root/app"
version=$(defaults read "$PWD/build/Build/Products/Release/Tack.app/Contents/Info.plist" CFBundleShortVersionString)
out="$root/dist/v$version"
mkdir -p "$out"
mv "$root/dist/Tack-$version.dmg" "$out/"
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/kelvin-weng/Tack/releases/download/v$version/" \
  --maximum-deltas 0 "$out"
echo "Ready to upload: $out"
