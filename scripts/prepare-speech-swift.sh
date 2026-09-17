#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEECH_SWIFT_DIR="$ROOT_DIR/external/speech-swift-worktree"
MLX_PACKAGE="$ROOT_DIR/.build/checkouts/mlx-swift/Package.swift"

if [[ ! -d "$SPEECH_SWIFT_DIR" ]]; then
  echo "Missing speech-swift checkout: $SPEECH_SWIFT_DIR" >&2
  echo "Clone https://github.com/soniqo/speech-swift into external/speech-swift-worktree." >&2
  exit 1
fi

cd "$ROOT_DIR"
swift package resolve

if [[ ! -f "$MLX_PACKAGE" ]]; then
  echo "Missing resolved mlx-swift package: $MLX_PACKAGE" >&2
  exit 1
fi

chmod u+w "$MLX_PACKAGE"

if ! grep -B1 '"mlx/mlx/backend/cpu/compiled.cpp"' "$MLX_PACKAGE" | grep -q '"mlx-generated/metal"'; then
  perl -0pi -e 's|("mlx/mlx/backend/cpu/compiled\.cpp",)|"mlx-generated/metal",\n            $1|' "$MLX_PACKAGE"
fi

if ! grep -B1 '"mlx/mlx/backend/metal/kernels"' "$MLX_PACKAGE" | grep -q '"mlx-generated/metal"'; then
  perl -0pi -e 's|("mlx/mlx/backend/metal/kernels",)|"mlx-generated/metal",\n        $1|' "$MLX_PACKAGE"
fi
