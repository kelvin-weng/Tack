#!/bin/zsh
# Builds Tack (Release) and installs it as /Applications/Tack.app, replacing any copy there, then opens it.
set -euo pipefail
cd "$(dirname "$0")/../app"
xcodebuild -project Tack.xcodeproj -scheme Tack -configuration Release -derivedDataPath build build -quiet
pkill -x Tack || true
sleep 1
rm -rf /Applications/Tack.app
ditto build/Build/Products/Release/Tack.app /Applications/Tack.app
open /Applications/Tack.app
echo "Installed /Applications/Tack.app"
