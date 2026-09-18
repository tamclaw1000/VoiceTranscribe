#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

duration="${DURATION:-20}"
duration="${duration#\{}"
duration="${duration%\}}"

source_name="Star Trek - The Next Generation (1987) - S02E04 - The Outrageous Okona - 1988-12-12.avi"
if [[ -f "$repo_root/samples/$source_name" ]]; then
  default_input="$repo_root/samples/$source_name"
else
  default_input="$repo_root/$source_name"
fi
default_output="$repo_root/samples/star-trek-first-${duration}s.wav"

input="${1:-$default_input}"
output="${2:-$default_output}"


if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "error: ffmpeg is required to extract the audio sample." >&2
  echo "Install it with: brew install ffmpeg" >&2
  exit 1
fi

if [[ ! -f "$input" ]]; then
  echo "error: input video not found: $input" >&2
  exit 1
fi

mkdir -p "$(dirname "$output")"

ffmpeg_log="$(mktemp -t voicetranscribe-ffmpeg.XXXXXX)"
trap 'rm -f "$ffmpeg_log"' EXIT

if ! ffmpeg \
  -hide_banner \
  -loglevel error \
  -y \
  -ss 0 \
  -err_detect ignore_err \
  -t "$duration" \
  -i "$input" \
  -vn \
  -ac 1 \
  -ar 16000 \
  -c:a pcm_s16le \
  "$output" 2>"$ffmpeg_log"; then
  cat "$ffmpeg_log" >&2
  exit 1
fi

echo "Wrote audio sample: $output"
