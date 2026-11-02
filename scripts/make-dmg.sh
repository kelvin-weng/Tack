#!/bin/zsh
# Builds Tack (Release) and packages it as dist/Tack-<version>.dmg: the app plus an Applications shortcut to drag it onto.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/app"
# The generic destination builds for both Apple and Intel chips, not just this Mac.
xcodebuild -project Tack.xcodeproj -scheme Tack -configuration Release -destination "generic/platform=macOS" -derivedDataPath build build -quiet
app="build/Build/Products/Release/Tack.app"
version=$(defaults read "$PWD/$app/Contents/Info.plist" CFBundleShortVersionString)

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Tack.app"
ln -s /Applications "$stage/Applications"

mkdir -p "$root/dist"
dmg="$root/dist/Tack-$version.dmg"
rm -f "$dmg"
hdiutil create -volname Tack -srcfolder "$stage" -format UDZO -fs APFS "$dmg" -quiet
# The DMG stays unsigned on purpose: macOS blocks a signed but un-notarised DMG on opening, and the app inside is signed.
echo "Built $dmg"
