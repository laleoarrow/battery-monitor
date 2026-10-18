#!/bin/bash
# Hidden production-renderer captures: never presents a window or native menu.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$#" != 1 ]]; then
    echo 'usage: verify_ring_metrics.sh OUTPUT_DIRECTORY' >&2
    exit 64
fi
RESULTS="$1"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$RESULTS" "$ROOT_DIR/.build/ring-metrics-capture.noindex"
RESULTS="$(cd "$RESULTS" && pwd)"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/ring-metrics-capture.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
APP_DIR="$BUILD_DIR/RingMetricsProbe.app"
TEST_BUNDLE_ID="com.leoarrow.wattson.ringmetricsqa.$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
wattson_cleanup_add_app "$APP_DIR"
wattson_cleanup_add_defaults "$TEST_BUNDLE_ID"
wattson_cleanup_add_container "$TEST_BUNDLE_ID"
wattson_cleanup_add_executable "$APP_DIR/Contents/MacOS/RingMetricsProbe"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR"/design/icon/in-app-logo/*.png "$APP_DIR/Contents/Resources/"
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>RingMetricsProbe</string>
<key>CFBundleIdentifier</key><string>${TEST_BUNDLE_ID}</string>
<key>CFBundleExecutable</key><string>RingMetricsProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$(cat "$ROOT_DIR/VERSION")</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
wattson_run xcrun swiftc "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift "$ROOT_DIR/tests/visual/capture_ring_metrics.swift" \
    -D DEBUG -swift-version 5 -warnings-as-errors -framework AppKit -framework IOKit \
    -o "$APP_DIR/Contents/MacOS/RingMetricsProbe" > "$RESULTS/build.log" 2>&1
wattson_run codesign --force --sign - "$APP_DIR" >> "$RESULTS/build.log" 2>&1
printf 'bundleID=%s\nbundlePath=%s\nmethod=hidden-production-renderers\n' "$TEST_BUNDLE_ID" "$APP_DIR" > "$RESULTS/capture-provenance.txt"
/usr/bin/shasum -a 256 "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR"/MenuBar/*.swift "$ROOT_DIR/tests/visual/capture_ring_metrics.swift" \
    "$APP_DIR/Contents/MacOS/RingMetricsProbe" > "$RESULTS/capture-inputs.sha256"
wattson_run_timeout 120 /usr/bin/env WATTSON_FORCE_REDUCE_MOTION=1 \
    WATTSON_FORCE_REDUCE_TRANSPARENCY=1 \
    "$APP_DIR/Contents/MacOS/RingMetricsProbe" "$RESULTS" > "$RESULTS/run.log" 2> "$RESULTS/run.err"
[[ -s "$RESULTS/evidence.json" ]]
cat "$RESULTS/run.log"
