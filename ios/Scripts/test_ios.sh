#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
FUSION_IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FUSION_SIMULATOR_ID="${FUSION_SIMULATOR_ID:-$(xcrun simctl list devices available -j | /usr/bin/python3 -c 'import json,sys; devices=json.load(sys.stdin)["devices"]; print(next(d["udid"] for group in devices.values() for d in group if d["name"].startswith("iPhone")))')}"
xcodebuild -project "$FUSION_IOS_ROOT/FusionIME.xcodeproj" -scheme FusionIME \
  -configuration Debug -destination "platform=iOS Simulator,id=$FUSION_SIMULATOR_ID" \
  -derivedDataPath "${TMPDIR:-/tmp}/FusionIME-Integration" -parallel-testing-enabled NO \
  -jobs 4 ARCHS=arm64 CODE_SIGNING_ALLOWED=NO test
