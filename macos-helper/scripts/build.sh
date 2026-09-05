#!/bin/bash
set -euo pipefail
helper_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$helper_root"
mkdir -p .build/direct
target="$(uname -m)-apple-macosx13.0"
swiftc -target "$target" -swift-version 5 -O -emit-library -static -emit-module -module-name LampCore \
  Sources/LampCore/*.swift -o .build/direct/libLampCore.a \
  -emit-module-path .build/direct/LampCore.swiftmodule
swiftc -target "$target" -swift-version 5 -O -I .build/direct -L .build/direct -lLampCore \
  Sources/MoonsideAgentLamp/main.swift -o .build/direct/MoonsideAgentLamp
app="$helper_root/dist/Moonside Agent Lamp.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/direct/MoonsideAgentLamp "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --options runtime --entitlements Resources/Entitlements.plist \
  --sign "${MOONSIDE_SIGN_IDENTITY:--}" "$app"
codesign --verify --strict --verbose=2 "$app"
plutil -lint "$app/Contents/Info.plist"
printf 'Built %s\n' "$app"
