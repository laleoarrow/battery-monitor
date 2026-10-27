#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
HERE="$ROOT_DIR/design/release-v5.0.2/diagnostics/history-presentation-observation"
OUTPUT_DIR="$1"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/history-presentation.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/history-presentation.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
SUITE="Wattson.SettingsCommandInteraction.$(/usr/bin/uuidgen)"
wattson_cleanup_add_defaults "$SUITE"
for strategy in baseline candidate; do
    APP_DIR="$BUILD_DIR/$strategy.app"
    IDENTIFIER="com.leoarrow.wattson.interactiontests.history.$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
    wattson_cleanup_add_defaults "$IDENTIFIER"
    wattson_cleanup_add_app "$APP_DIR"
    wattson_cleanup_add_container "$IDENTIFIER"
    wattson_cleanup_add_executable "$APP_DIR/Contents/MacOS/Probe"
    mkdir -p "$APP_DIR/Contents/MacOS" "$BUILD_DIR/$strategy-source"
    cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleName</key><string>History Presentation Diagnostic</string><key>CFBundleIdentifier</key><string>$IDENTIFIER</string><key>CFBundleExecutable</key><string>Probe</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
EOF
    wattson_run_timeout 20 /usr/bin/python3 "$HERE/extract.py" "$ROOT_DIR/tests/interaction/main.swift" \
        "$BUILD_DIR/$strategy-source/main.swift" "$strategy" > "$OUTPUT_DIR/$strategy-extraction.json"
    /bin/cp "$BUILD_DIR/$strategy-source/main.swift" "$OUTPUT_DIR/$strategy-main.swift"
    wattson_run_timeout 240 xcrun swiftc "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift \
        "$ROOT_DIR"/Popover/*.swift "$BUILD_DIR/$strategy-source/main.swift" -D DEBUG -swift-version 5 \
        -framework AppKit -framework CoreGraphics -framework IOKit \
        -o "$APP_DIR/Contents/MacOS/Probe" > "$OUTPUT_DIR/$strategy-build.log" 2>&1
    wattson_run_timeout 20 codesign --force --sign - "$APP_DIR" >> "$OUTPUT_DIR/$strategy-build.log" 2>&1
    /usr/bin/shasum -a 256 "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift "$ROOT_DIR"/Popover/*.swift \
        "$BUILD_DIR/$strategy-source/main.swift" "$APP_DIR/Contents/MacOS/Probe" > "$OUTPUT_DIR/$strategy-source-digests.txt"
done
for case_name in baseline candidate infinite long retained; do
    strategy=candidate; fault=none
    if [[ "$case_name" == baseline ]]; then strategy=baseline
    elif [[ "$case_name" != candidate ]]; then fault="$case_name"; fi
    status=0
    wattson_run_timeout 30 /usr/bin/env WATTSON_FORCE_REDUCE_MOTION=0 WATTSON_HISTORY_FAULT="$fault" \
        WATTSON_TEST_DEFAULTS_SUITE="$SUITE" "$BUILD_DIR/$strategy.app/Contents/MacOS/Probe" \
        "$OUTPUT_DIR/$case_name.json" > "$OUTPUT_DIR/$case_name.log" 2>&1 || status=$?
    printf '%s\n' "$status" > "$OUTPUT_DIR/$case_name-exit-code.txt"
    [[ -s "$OUTPUT_DIR/$case_name.json" ]] || exit 1
done
wattson_run_timeout 20 /usr/bin/python3 "$HERE/review.py" "$OUTPUT_DIR" > "$OUTPUT_DIR/paired-results.json"
