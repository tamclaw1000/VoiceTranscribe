#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VoiceTranscribe"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
if [[ "${PACKAGE_APP_SKIP_BUILD:-0}" != "1" ]]; then
  swift package clean
  "$ROOT_DIR/scripts/prepare-speech-swift.sh"
  swift build -c "$CONFIGURATION"
fi
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BIN_PATH/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --entitlements "$ROOT_DIR/Resources/VoiceTranscribe.entitlements" "$APP_DIR"
fi

echo "$APP_DIR"
