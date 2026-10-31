#!/bin/bash
# Actual animation capture is confined to an owned disposable ARM GUI VM.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$#" != 1 || "${WATTSON_RUN_GUI_TESTS:-}" != 1 || "$(/usr/sbin/sysctl -n hw.model)" != VirtualMac* ]]; then
    echo 'usage (disposable macOS VM only): WATTSON_RUN_GUI_TESTS=1 verify_scrollbar.sh OUTPUT_DIRECTORY' >&2
    exit 64
fi
RESULTS="$1"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$RESULTS" "$ROOT_DIR/.build/scrollbar-capture.noindex"
RESULTS="$(cd "$RESULTS" && pwd)"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/scrollbar-capture.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
APP_DIR="$BUILD_DIR/ScrollbarProbe.app"
# Reuse the GUI VM audit's existing capture-domain allowlist.
TEST_BUNDLE_ID="com.leoarrow.wattson.topprocessesqa.$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
wattson_cleanup_add_app "$APP_DIR"
wattson_cleanup_add_defaults "$TEST_BUNDLE_ID"
wattson_cleanup_add_container "$TEST_BUNDLE_ID"
wattson_cleanup_add_executable "$APP_DIR/Contents/MacOS/ScrollbarProbe"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/bin/cp "$ROOT_DIR"/design/icon/in-app-logo/*.png "$APP_DIR/Contents/Resources/"
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ScrollbarProbe</string>
<key>CFBundleIdentifier</key><string>${TEST_BUNDLE_ID}</string>
<key>CFBundleExecutable</key><string>ScrollbarProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$(cat "$ROOT_DIR/VERSION")</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
wattson_run xcrun clang -mmacosx-version-min=12.0 -Wno-deprecated-declarations \
    -c "$ROOT_DIR/tests/visual/capture_glass_shadow.c" -o "$BUILD_DIR/capture.o" > "$RESULTS/build.log" 2>&1
wattson_run xcrun swiftc "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift "$ROOT_DIR/tests/visual/capture_scrollbar.swift" \
    "$BUILD_DIR/capture.o" -D DEBUG -swift-version 5 -warnings-as-errors \
    -import-objc-header "$ROOT_DIR/tests/visual/capture_glass_shadow.h" \
    -framework AppKit -framework CoreGraphics -framework IOKit \
    -o "$APP_DIR/Contents/MacOS/ScrollbarProbe" >> "$RESULTS/build.log" 2>&1
wattson_run codesign --force --sign - "$APP_DIR" >> "$RESULTS/build.log" 2>&1
printf 'bundleID=%s\nbundlePath=%s\nmethod=owned-window-production-scrollbar\n' "$TEST_BUNDLE_ID" "$APP_DIR" > "$RESULTS/capture-provenance.txt"
/usr/bin/shasum -a 256 "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR"/MenuBar/*.swift "$ROOT_DIR/tests/visual/capture_scrollbar.swift" \
    "$APP_DIR/Contents/MacOS/ScrollbarProbe" > "$RESULTS/capture-inputs.sha256"
wattson_run_timeout 120 /usr/bin/env WATTSON_FORCE_REDUCE_MOTION=0 \
    WATTSON_FORCE_REDUCE_TRANSPARENCY=0 WATTSON_FORCE_INCREASE_CONTRAST=0 \
    "$APP_DIR/Contents/MacOS/ScrollbarProbe" "$RESULTS" > "$RESULTS/run.log" 2> "$RESULTS/run.err"
[[ -s "$RESULTS/evidence.json" ]]
cat "$RESULTS/run.log"
