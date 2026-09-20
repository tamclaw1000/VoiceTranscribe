#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
# package-app.sh reads CONFIGURATION too, and defaults to debug. Without this
# export it would package the debug binary while this script built release.
export CONFIGURATION

cd "$ROOT_DIR"

# Validate prerequisites before the clean step. `swift package clean` walks up to
# the package root and deletes build products, so a failure after it would leave
# the checkout with no build at all.
if [[ ! -f "$ROOT_DIR/Package.swift" ]]; then
  echo "Missing Package.swift at $ROOT_DIR" >&2
  exit 1
fi

if [[ ! -x "$SCRIPT_DIR/prepare-speech-swift.sh" ]]; then
  echo "Missing or non-executable $SCRIPT_DIR/prepare-speech-swift.sh" >&2
  exit 1
fi

if [[ ! -d "$ROOT_DIR/external/speech-swift-worktree" ]]; then
  echo "Missing dependency checkout: $ROOT_DIR/external/speech-swift-worktree" >&2
  echo "Clone https://github.com/soniqo/speech-swift into external/speech-swift-worktree." >&2
  exit 1
fi

swift package clean
"$SCRIPT_DIR/prepare-speech-swift.sh"
swift build -c "$CONFIGURATION"
PACKAGE_APP_SKIP_BUILD=1 "$SCRIPT_DIR/package-app.sh"

APP_BIN="$ROOT_DIR/dist/VoiceTranscribe.app/Contents/MacOS/VoiceTranscribe"
if [[ ! -x "$APP_BIN" ]]; then
  echo "Packaging did not produce $APP_BIN" >&2
  exit 1
fi

echo "$APP_BIN"
