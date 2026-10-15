#!/bin/bash
# Runs tests/interaction against real AppKit objects.
#
# The rest of the suite reads the sources; this one executes them. It exists
# because the click and popover paths are AppKit-timing dependent, and reading
# the code did not catch either of the two bugs it found: a press held past a
# coalescing window acted twice, and a click that reopened the popover during
# its close animation was swallowed.
#
# Needs a real .app bundle — the status item has to be able to host a popover —
# and a logged-in GUI session. No sudo or installation; its unique sandbox
# container and test preferences are removed when the harness finishes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/interaction.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/interaction.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
APP_DIR="$BUILD_DIR/InteractionTests.app"
TEST_BUNDLE_ID="com.leoarrow.wattson.interactiontests.$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
WATTSON_TEST_DEFAULTS_SUITE="Wattson.SettingsCommandInteraction.$(/usr/bin/uuidgen)"
export WATTSON_TEST_DEFAULTS_SUITE
wattson_cleanup_add_defaults "$WATTSON_TEST_DEFAULTS_SUITE"
wattson_cleanup_add_container "$TEST_BUNDLE_ID"
wattson_cleanup_add_app "$APP_DIR"

mkdir -p "$APP_DIR/Contents/MacOS" "$BUILD_DIR/isolated-home"

cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>InteractionTests</string>
    <key>CFBundleIdentifier</key><string>${TEST_BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>InteractionTests</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# -D DEBUG exposes what AppKit is drawing, which `isOpen` deliberately does not.
wattson_run xcrun swiftc \
    "$ROOT_DIR"/Core/*.swift \
    "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR/tests/interaction/main.swift" \
    -D DEBUG \
    -framework AppKit \
    -framework CoreGraphics \
    -framework IOKit \
    -o "$APP_DIR/Contents/MacOS/InteractionTests"

# Sandboxed like the shipping app, so the helper query on open behaves the same.
wattson_run codesign --force --sign - \
    --entitlements "$ROOT_DIR/BatteryPowerApp.entitlements" \
    "$APP_DIR" >/dev/null 2>&1

POWER_MODE="$(/usr/bin/pmset -g live | awk 'tolower($1) == "powermode" { print $2; exit }')"
wattson_run_timeout 240 /usr/bin/env \
    CFFIXED_USER_HOME="$BUILD_DIR/isolated-home" \
    WATTSON_EXPECTED_POWER_MODE="$POWER_MODE" \
    "$APP_DIR/Contents/MacOS/InteractionTests"
