#!/bin/bash
# Production AppKit latency measurements; --run-gui requires a disposable,
# logged-in GUI session. --compile-only never creates visible UI.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---compile-only}"
if [[ "$MODE" != --compile-only && "$MODE" != --run-gui ]] || (( $# > 2 )); then
    echo "usage: $0 --compile-only | --run-gui OUTPUT.jsonl" >&2
    exit 64
fi
if [[ "$MODE" == --run-gui && ( $# != 2 || -e "$2" ) ]]; then
    echo "--run-gui needs a new caller-owned output file" >&2
    exit 64
fi
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/ui-latency.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/ui-latency.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
APP_DIR="$BUILD_DIR/UILatency.app"
TEST_BUNDLE_ID="com.leoarrow.wattson.uilatency.$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
export WATTSON_TEST_DEFAULTS_SUITE="Wattson.UILatency.$(/usr/bin/uuidgen)"
wattson_cleanup_add_defaults "$WATTSON_TEST_DEFAULTS_SUITE"
wattson_cleanup_add_container "$TEST_BUNDLE_ID"
wattson_cleanup_add_app "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR/isolated-home"
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>UILatency</string>
<key>CFBundleIdentifier</key><string>${TEST_BUNDLE_ID}</string>
<key>CFBundleExecutable</key><string>UILatency</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
for resource in AppLogoColor AppLogoClearLight AppLogoClearDark; do
    /bin/cp "$ROOT_DIR/design/icon/in-app-logo/${resource}.png" "$APP_DIR/Contents/Resources/"
done
wattson_run xcrun swiftc "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift "$ROOT_DIR/tests/performance/ui-latency.swift" \
    -O -D DEBUG -parse-as-library -framework AppKit -framework CoreGraphics -framework IOKit \
    -o "$APP_DIR/Contents/MacOS/UILatency"
wattson_run codesign --force --sign - --entitlements "$ROOT_DIR/BatteryPowerApp.entitlements" "$APP_DIR" >/dev/null 2>&1
if [[ "$MODE" == --compile-only ]]; then
    echo "UI_LATENCY_COMPILE_OK"
    exit 0
fi
export WATTSON_PERF_SOURCE_REVISION="${WATTSON_PERF_SOURCE_REVISION:-$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)}"
wattson_run_timeout 900 /usr/bin/env CFFIXED_USER_HOME="$BUILD_DIR/isolated-home" \
    "$APP_DIR/Contents/MacOS/UILatency" > "$2"
