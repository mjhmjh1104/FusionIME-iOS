#!/bin/bash
set -euo pipefail
FUSION_IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if ! xcrun --sdk iphonesimulator --show-sdk-path >/dev/null 2>&1; then
  echo 'Xcode와 iOS Simulator SDK가 필요합니다. Command Line Tools만으로는 iOS 타깃을 빌드할 수 없습니다.' >&2
  exit 2
fi
xcodebuild -project "$FUSION_IOS_ROOT/FusionIME.xcodeproj" -scheme FusionIME \
  -configuration "${CONFIGURATION:-Debug}" -destination "${DESTINATION:-generic/platform=iOS Simulator}" \
  -derivedDataPath "${TMPDIR:-/tmp}/FusionIME-DerivedData" -jobs 4 ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
