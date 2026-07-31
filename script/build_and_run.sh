#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Wattson"
BUNDLE_ID="com.leoarrow.wattson"
MIN_SYSTEM_VERSION="12.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

xcrun swiftc \
    "$ROOT_DIR"/Core/*.swift \
    "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR/BatteryPowerWidget.swift" \
    "$ROOT_DIR/main.swift" \
    -framework AppKit \
    -framework CoreGraphics \
    -framework IOKit \
    -framework WidgetKit \
    -D DEBUG \
    -o "$APP_BINARY"
chmod +x "$APP_BINARY"

cat > "$INFO_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [ -f "$ROOT_DIR/design/icon/AppIcon.icns" ]; then
    cp "$ROOT_DIR/design/icon/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

codesign --force --sign - --entitlements "$ROOT_DIR/BatteryPowerApp.entitlements" "$APP_BUNDLE" >/dev/null

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        open_app
        sleep 2
        pgrep -x "$APP_NAME" >/dev/null
        ;;
    --preview|preview)
        /usr/bin/open -n "$APP_BUNDLE" --args --popover-preview "${@:2}"
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--preview [--preview-state=STATE]]" >&2
        exit 2
        ;;
esac
