#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="VoiceTranscribe"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
PACKAGE_SCRIPT="$SCRIPT_DIR/package-app.sh"
SKIP_BUILD="${SKIP_BUILD:-0}"

usage() {
  cat <<USAGE
Usage: ./scripts/run.sh [--no-build]

Builds and packages VoiceTranscribe, then launches the app bundle.

Options:
  --no-build   Launch the existing dist/VoiceTranscribe.app without rebuilding.
  -h, --help   Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      SKIP_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$SKIP_BUILD" != "1" ]]; then
  "$PACKAGE_SCRIPT" >/dev/null
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "App bundle not found: $APP_DIR" >&2
  echo "Run ./scripts/run.sh without --no-build to create it." >&2
  exit 1
fi

open -n "$APP_DIR"
echo "Launched $APP_DIR"
