#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
HERE="$ROOT_DIR/design/release-v5.0.2/diagnostics/history-retarget-timing"
OUTPUT_DIR="$1"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/history-retarget.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/history-retarget.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
APP_DIR="$BUILD_DIR/RetargetProbe.app"
IDENTIFIER="com.leoarrow.wattson.interactiontests.history.$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
wattson_cleanup_add_defaults "$IDENTIFIER"
wattson_cleanup_add_app "$APP_DIR"
wattson_cleanup_add_container "$IDENTIFIER"
wattson_cleanup_add_executable "$APP_DIR/Contents/MacOS/Probe"
mkdir -p "$APP_DIR/Contents/MacOS"
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleName</key><string>History Retarget Diagnostic</string><key>CFBundleIdentifier</key><string>$IDENTIFIER</string><key>CFBundleExecutable</key><string>Probe</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
EOF
wattson_run_timeout 20 /usr/bin/python3 -B "$HERE/extract.py" "$ROOT_DIR/tests/interaction/main.swift" \
    "$BUILD_DIR/main.swift" > "$OUTPUT_DIR/extraction.json"
/bin/cp "$BUILD_DIR/main.swift" "$OUTPUT_DIR/extracted-main.swift"
wattson_run_timeout 240 xcrun swiftc "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift "$BUILD_DIR/main.swift" -D DEBUG -swift-version 5 \
    -framework AppKit -framework CoreGraphics -framework IOKit \
    -o "$APP_DIR/Contents/MacOS/Probe" > "$OUTPUT_DIR/build.log" 2>&1
wattson_run_timeout 20 codesign --force --sign - "$APP_DIR" >> "$OUTPUT_DIR/build.log" 2>&1
/usr/bin/shasum -a 256 "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR/tests/interaction/main.swift" "$BUILD_DIR/main.swift" \
    "$APP_DIR/Contents/MacOS/Probe" > "$OUTPUT_DIR/source-digests.txt"
for case_name in baseline baseline-delayed fixed fixed-delayed; do
    fixed=0; delayed=0
    case "$case_name" in fixed*) fixed=1 ;; esac
    case "$case_name" in *-delayed) delayed=1 ;; esac
    SUITE="Wattson.SettingsCommandInteraction.$(/usr/bin/uuidgen)"
    wattson_cleanup_add_defaults "$SUITE"
    status=0
    wattson_run_timeout 60 /usr/bin/env WATTSON_FORCE_REDUCE_MOTION=0 WATTSON_FORCE_REDUCE_TRANSPARENCY=0 \
        WATTSON_RETARGET_FIXED_CLOCK="$fixed" WATTSON_RETARGET_DELAY="$delayed" \
        WATTSON_TEST_DEFAULTS_SUITE="$SUITE" "$APP_DIR/Contents/MacOS/Probe" \
        "$OUTPUT_DIR/$case_name.json" > "$OUTPUT_DIR/$case_name.log" 2>&1 || status=$?
    printf '%s\n' "$status" > "$OUTPUT_DIR/$case_name-exit-code.txt"
    [[ -s "$OUTPUT_DIR/$case_name.json" ]] || exit 1
done
wattson_run_timeout 20 /usr/bin/python3 -B "$HERE/review.py" "$OUTPUT_DIR" > "$OUTPUT_DIR/comparison.json"
