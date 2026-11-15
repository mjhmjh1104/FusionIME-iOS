#!/bin/bash
# Prepare missing generated resources, then build the iOS app and keyboard.
set -euo pipefail
FUSION_ROOT="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

case "${1:-}" in
  --help|-h)
    cat <<'USAGE'
Usage: ./build.sh [--prepare-only]

Requires an Apple Silicon Mac, Xcode and Python 3.10+.
The first build also needs Bazelisk, Rust 1.88+ and these Rust targets:
  aarch64-apple-darwin, aarch64-apple-ios, aarch64-apple-ios-sim
For example, with Homebrew and rustup installed:
  brew install bazelisk
  rustup target add aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim

Missing dictionaries and XCFrameworks are generated automatically. The first
build downloads pinned upstream sources and native build dependencies.
--prepare-only generates resources without building the app (also used by CI).

Default: unsigned Debug build for iOS Simulator.
Device build:
  CONFIGURATION=Release DESTINATION='generic/platform=iOS' ./build.sh
After preparation, open ios/FusionIME.xcodeproj to sign and run on a device.

Overrides: DEVELOPER_DIR, FUSION_BAZELISK, FUSION_CARGO, FUSION_NATIVE_CACHE.
USAGE
    exit 0 ;;
  ""|--prepare-only) ;;
  *) echo "Unknown option: $1 (see ./build.sh --help)" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  echo "Only one option is accepted (see ./build.sh --help)." >&2
  exit 2
fi

python3 "$FUSION_ROOT/ios/Scripts/prepare_build.py"
if [[ "${1:-}" != --prepare-only ]]; then
  exec bash "$FUSION_ROOT/ios/Scripts/build_ios.sh"
fi
