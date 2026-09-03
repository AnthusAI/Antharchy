#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${1:-$REPO_ROOT/dist}"

mkdir -p "$OUTPUT_DIR"

export ANTHARCHY_SRC="$REPO_ROOT"

echo "=== Building antharchy-settings ==="
(
  cd "$SCRIPT_DIR/antharchy-settings"
  makepkg -f --noconfirm --nodeps
  mv -f *.pkg.tar.zst "$OUTPUT_DIR/"
)

echo "=== Building antharchy ==="
(
  cd "$SCRIPT_DIR/antharchy"
  makepkg -f --noconfirm --nodeps
  mv -f *.pkg.tar.zst "$OUTPUT_DIR/"
)

echo "=== Generating pacman repo database ==="
(
  cd "$OUTPUT_DIR"
  repo-add -n antharchy.db.tar.zst *.pkg.tar.zst
)

echo "=== Build Complete ==="
ls -lh "$OUTPUT_DIR"
