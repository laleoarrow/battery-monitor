#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="WattsonPreview"
BUNDLE_ID="com.leoarrow.wattson.preview"
BASE_BUNDLE_ID="$BUNDLE_ID"
LOG_SUBSYSTEM="com.leoarrow.wattson"
DISPLAY_NAME="Wattson Preview"
MIN_SYSTEM_VERSION="12.0"
SWIFT_TARGET="arm64-apple-macos12.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="$(tr -d '\r\n' < "$ROOT_DIR/VERSION")"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
case "$MODE" in
    run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--preview|preview) ;;
    *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--preview [--preview-state=STATE]]" >&2; exit 2 ;;
esac

wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/run.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/run.noindex/session.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
BUNDLE_ID="$BASE_BUNDLE_ID.$(/usr/bin/basename "$BUILD_DIR")"
wattson_cleanup_add_container "$BUNDLE_ID"
APP_BUNDLE="$BUILD_DIR/$DISPLAY_NAME.app"
LEGACY_APP_BUNDLE="$ROOT_DIR/dist/Wattson.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

wattson_cleanup_add_app "$APP_BUNDLE"
wattson_cleanup_add_executable "$APP_BINARY"

# Remove only the identified obsolete developer preview, never a release app.
if [[ -e "$LEGACY_APP_BUNDLE" || -L "$LEGACY_APP_BUNDLE" ]]; then
    [[ ! -L "$LEGACY_APP_BUNDLE" ]] || { echo "Refusing a symlinked legacy preview" >&2; exit 2; }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LEGACY_APP_BUNDLE/Contents/Info.plist")" == "$BASE_BUNDLE_ID" ]] \
        || { echo "Refusing to remove an unrelated dist app" >&2; exit 2; }
    wattson_stop_executable "$LEGACY_APP_BUNDLE/Contents/MacOS/$APP_NAME"
    wattson_unregister_app "$LEGACY_APP_BUNDLE"
    rm -rf "$LEGACY_APP_BUNDLE"
fi

mkdir -p "$APP_MACOS" "$APP_RESOURCES"

wattson_run xcrun swiftc \
    "$ROOT_DIR"/Core/*.swift \
    "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR/main.swift" \
    -target "$SWIFT_TARGET" \
    -framework AppKit \
    -framework CoreGraphics \
    -framework IOKit \
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
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
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

/usr/bin/codesign --force --sign - --entitlements "$ROOT_DIR/BatteryPowerApp.entitlements" "$APP_BUNDLE" >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
touch "$APP_BUNDLE"

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
    run)
        wattson_run /usr/bin/open -n -W "$APP_BUNDLE"
        ;;
    --debug|debug)
        wattson_run lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        wattson_run /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        wattson_run /usr/bin/log stream --info --style compact --predicate "subsystem == \"$LOG_SUBSYSTEM\""
        ;;
    --verify|verify)
        open_app
        sleep 2
        /bin/ps -axo comm= | /usr/bin/grep -Fx -- "$APP_BINARY" >/dev/null
        ;;
    --preview|preview)
        wattson_run /usr/bin/open -n -W "$APP_BUNDLE" --args --popover-preview "${@:2}"
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--preview [--preview-state=STATE]]" >&2
        exit 2
        ;;
esac
