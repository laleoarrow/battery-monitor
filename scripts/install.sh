#!/bin/bash
# install.sh — Install Wattson as a macOS menu bar app
#
# --app-only skips step 7. The app itself lives in ~/Applications and needs no
# elevation; only the privileged helper does. The helper changes rarely, so
# updating the app should not have to ask for a password.
set -euo pipefail

APP_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --app-only) APP_ONLY=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
APP_NAME="Wattson"
APP_VERSION="${WATTSON_APP_VERSION:-2.1.3}"
SWIFT_TARGET="arm64-apple-macos12.0"
APP_DIR="$HOME/Applications/Wattson.app"
APP_BUNDLE_ID="com.leoarrow.wattson"
SUPPORT_DIR="$HOME/Library/Application Support/Wattson"
HELPER_LABEL="com.leoarrow.wattson.helper"
HELPER_TARGET="system/$HELPER_LABEL"
HELPER_PLIST="/Library/LaunchDaemons/${HELPER_LABEL}.plist"
HELPER_BIN="/Library/PrivilegedHelperTools/${HELPER_LABEL}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
LAUNCH_DOMAIN="gui/$(id -u)"

LEGACY_APP="$HOME/Applications/电池功率.app"
LEGACY_BUNDLE_ID="com.leoarrow.battery-monitor"
LEGACY_AGENT="$HOME/Library/LaunchAgents/${LEGACY_BUNDLE_ID}.agent.plist"
LEGACY_AGENT_OLD="$HOME/Library/LaunchAgents/${LEGACY_BUNDLE_ID}.plist"
LEGACY_SUPPORT="$HOME/Library/Application Support/电池功率"
LEGACY_CONFIG="$HOME/.battery_monitor.cfg"
LEGACY_SCRIPT="$HOME/.battery_monitor.py"

APP_ENTITLEMENTS="$ROOT_DIR/BatteryPowerApp.entitlements"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wattson-build.XXXXXX")"
cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

echo "📦 Installing ${APP_NAME}..."

# 1. Remove the old install completely. Unregister before deleting, otherwise
# LaunchServices keeps a stale record pointing at a missing bundle.
launchctl bootout "$LAUNCH_DOMAIN" "$LEGACY_AGENT" >/dev/null 2>&1 || true
launchctl bootout "$LAUNCH_DOMAIN" "$LEGACY_AGENT_OLD" >/dev/null 2>&1 || true
rm -f "$LEGACY_AGENT" "$LEGACY_AGENT_OLD"
pkill -f "$LEGACY_APP/Contents/MacOS/applet" 2>/dev/null || true
if [ -d "$LEGACY_APP" ]; then
    xcrun pluginkit -r "$LEGACY_APP/Contents/PlugIns/BatteryPowerWidgetExtension.appex" >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$LEGACY_APP" >/dev/null 2>&1 || true
fi
rm -rf "$LEGACY_APP" "$LEGACY_SUPPORT"
rm -f "$LEGACY_CONFIG" "$LEGACY_SCRIPT"
echo "  ✅ Removed 电池功率"

# 2. Recreate the app bundle.
pkill -f "$APP_DIR/Contents/MacOS/Wattson" 2>/dev/null || true
if [ -d "$APP_DIR" ]; then
    "$LSREGISTER" -u "$APP_DIR" >/dev/null 2>&1 || true
fi
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$SUPPORT_DIR"

# 3. Build. Top-level statements live in main.swift; every other source is a
# plain module file.
xcrun swiftc \
    "$ROOT_DIR"/Core/*.swift \
    "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR/main.swift" \
    -target "$SWIFT_TARGET" \
    -framework AppKit \
    -framework CoreGraphics \
    -framework IOKit \
    -O \
    -o "$APP_DIR/Contents/MacOS/Wattson"
chmod +x "$APP_DIR/Contents/MacOS/Wattson"
echo "  ✅ Native app → $APP_DIR/Contents/MacOS/Wattson"

# 4. Write bundle metadata.
cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${APP_BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>Wattson</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

mkdir -p "$APP_DIR/Contents/Resources/zh-Hans.lproj"
cat > "$APP_DIR/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" << 'EOF'
"CFBundleDisplayName" = "瓦特森";
"CFBundleName" = "瓦特森";
EOF
echo "  ✅ Info.plist"

# 5. Copy the application icon when present.
ICON_SRC="$ROOT_DIR/design/icon/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "  ✅ Icon"
else
    echo "  ⚠️  No AppIcon.icns found, skipping icon"
fi

# 6. Sign and register the app.
codesign --force --sign - --entitlements "$APP_ENTITLEMENTS" "$APP_DIR" >/dev/null
echo "  ✅ Ad-hoc code signature"
# Bumping the bundle's mtime before re-registering is what makes Finder and
# Spotlight pick up a changed icon; without it they keep serving the cached one.
touch "$APP_DIR"
"$LSREGISTER" -f "$APP_DIR" >/dev/null

# 7. Install the privileged helper. launchd wakes it on demand and it exits
# after five idle seconds.
if [ "$APP_ONLY" = "1" ]; then
    echo "  ⏭  Skipping the privileged helper (--app-only)"
    # -e, not -x: the helper is 544 root:wheel, so it is deliberately not
    # executable by the user running this script.
    if [ ! -e "$HELPER_BIN" ]; then
        echo "  ⚠️  No helper at $HELPER_BIN — power mode switching will not work."
        echo "     Run ./scripts/install.sh without --app-only to install it."
    fi
    echo ""
    echo "🎉 Done. Launch with: open \"$APP_DIR\""
    exit 0
fi
echo "  🔑 Installing the privileged helper (needs sudo once)"
HELPER_BUILD="$BUILD_DIR/wattson-helper"
xcrun swiftc "$ROOT_DIR/Helper/wattson-helper.swift" \
    -target "$SWIFT_TARGET" \
    -O \
    -o "$HELPER_BUILD"
codesign --force --sign - "$HELPER_BUILD" >/dev/null
helper_was_disabled=0
if ! disabled_services="$(sudo launchctl print-disabled system)"; then
    echo "helper launchd state could not be inspected" >&2
    exit 1
fi
case "$disabled_services" in
    *"\"$HELPER_LABEL\" => disabled"*|*"\"$HELPER_LABEL\" => true"*)
        helper_was_disabled=1
        ;;
esac
if sudo launchctl print "$HELPER_TARGET" >/dev/null 2>&1; then
    sudo launchctl bootout "$HELPER_TARGET"
    for ((helper_stop_attempt = 0; helper_stop_attempt < 10; helper_stop_attempt++)); do
        if ! sudo launchctl print "$HELPER_TARGET" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
    if sudo launchctl print "$HELPER_TARGET" >/dev/null 2>&1; then
        echo "existing helper service could not be stopped" >&2
        exit 1
    fi
fi
sudo mkdir -p /Library/PrivilegedHelperTools
sudo cp "$HELPER_BUILD" "$HELPER_BIN"
sudo chown root:wheel "$HELPER_BIN"
sudo chmod 544 "$HELPER_BIN"
sudo cp "$ROOT_DIR/Helper/${HELPER_LABEL}.plist" "$HELPER_PLIST"
sudo chown root:wheel "$HELPER_PLIST"
sudo chmod 644 "$HELPER_PLIST"
if [ "$helper_was_disabled" = "1" ]; then
    sudo launchctl enable "$HELPER_TARGET"
fi
if ! sudo launchctl bootstrap system "$HELPER_PLIST"; then
    if [ "$helper_was_disabled" = "1" ]; then
        sudo launchctl bootout "$HELPER_TARGET" >/dev/null 2>&1 || true
        sudo launchctl disable "$HELPER_TARGET" >/dev/null 2>&1 || true
    fi
    exit 1
fi
echo "  ✅ Helper installed (not running until you right-click)"

echo ""
echo "🎉 Done. Launch with: open \"$APP_DIR\""
