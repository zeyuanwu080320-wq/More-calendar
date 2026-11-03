#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -n "${SDK_PATH:-}" ]]; then
  SDK="$SDK_PATH"
elif [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]]; then
  SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
else
  SDK="$(xcrun --sdk macosx --show-sdk-path)"
fi

SCRATCH="$ROOT/.build/scratch"
CACHE="$ROOT/.build/cache"
CLANG_CACHE="$ROOT/.build/clangcache"
mkdir -p "$SCRATCH" "$CACHE" "$CLANG_CACHE" "$ROOT/build"

LOG="$ROOT/build/selftest.log"
set +e
CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" swift run \
  --disable-sandbox \
  --sdk "$SDK" \
  --cache-path "$CACHE" \
  --scratch-path "$SCRATCH" \
  --manifest-cache local \
  SchoolEventInboxSelfTest 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e

echo "Self-test log: $LOG"
exit "$STATUS"
