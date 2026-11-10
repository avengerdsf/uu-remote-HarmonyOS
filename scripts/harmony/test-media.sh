#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export TMPDIR="${UU_TMP_DIR:-$ROOT/tmp}"
mkdir -p "$TMPDIR"
BIN="$TMPDIR/media-pipeline-test"
trap 'rm -f -- "$BIN"' EXIT
g++ -std=c++17 -Wall -Wextra -Werror -pthread \
  -I"$ROOT/tests/harmony/media_pipeline" \
  -I"$ROOT/harmony/entry/src/main/cpp/include" \
  "$ROOT/tests/harmony/media_pipeline_test.cpp" \
  "$ROOT/harmony/entry/src/main/cpp/src/media_pipeline.cpp" -o "$BIN"
timeout 20 "$BIN" "$@"
