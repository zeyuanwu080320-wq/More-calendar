#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -n "${SDK_PATH:-}" ]]; then
  SDK="$SDK_PATH"
elif [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]]; then
  # This Mac has a Command Line Tools SDK that matches the installed Swift
  # compiler. Xcode users normally do not need this fallback.
  SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
else
  SDK="$(xcrun --sdk macosx --show-sdk-path)"
fi

SCRATCH="$ROOT/.build/scratch"
CACHE="$ROOT/.build/cache"
CLANG_CACHE="$ROOT/.build/clangcache"
mkdir -p "$SCRATCH" "$CACHE" "$CLANG_CACHE"

CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" swift build \
  --disable-sandbox \
  --sdk "$SDK" \
  --cache-path "$CACHE" \
  --scratch-path "$SCRATCH" \
  --manifest-cache local

BIN_DIR="$(CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" swift build --show-bin-path \
  --disable-sandbox \
  --sdk "$SDK" \
  --cache-path "$CACHE" \
  --scratch-path "$SCRATCH" \
  --manifest-cache local)"

# The bundle is named after the user-visible product name. The executable inside
# keeps its historical name (SchoolEventInbox) because CFBundleExecutable and the
# SwiftPM product name are unchanged; only the .app folder was renamed.
APP="$ROOT/../build/More calendar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/SchoolEventInbox" "$APP/Contents/MacOS/SchoolEventInbox"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
if [[ -d "$BIN_DIR/SchoolEventInbox_SchoolEventInbox.bundle" ]]; then
  cp -R "$BIN_DIR/SchoolEventInbox_SchoolEventInbox.bundle" "$APP/Contents/Resources/"
fi
# SwiftUI localization lookup uses the main bundle; copy the English table
# next to the resource bundle as well.
if [[ -d "$ROOT/Sources/SchoolEventInbox/Resources/en.lproj" ]]; then
  cp -R "$ROOT/Sources/SchoolEventInbox/Resources/en.lproj" "$APP/Contents/Resources/"
fi

# The icon is optional for source builds. Do not fail the build when it has
# not been generated; the app still runs with the system default icon.
ICON="$ROOT/AppIcon.icns"
if [[ -f "$ICON" ]]; then
  cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
  if /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP/Contents/Info.plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist"
  else
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
  fi
else
  echo "WARNING: $ICON not found; skipping app icon and CFBundleIconFile setup" >&2
fi

# A stable designated requirement keeps Keychain access working across local
# rebuilds. Without it, an ad-hoc signature's cdhash changes every build and
# macOS may treat the new binary as a different app.
codesign --force --deep --sign - --timestamp=none \
  --identifier "local.duishangque.SchoolEventInbox" \
  --requirements '=designated => identifier "local.duishangque.SchoolEventInbox"' \
  "$APP" >/dev/null
echo "Built $APP"
echo "SDK: $SDK"

if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
