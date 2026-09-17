#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"

cd "$ROOT_DIR"
swift package clean
"$ROOT_DIR/scripts/prepare-speech-swift.sh"
swift build -c "$CONFIGURATION"
