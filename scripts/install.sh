#!/bin/bash
# install.sh — Install Wattson as a macOS menu bar app
#
# --app-only skips step 7. The app itself lives in ~/Applications and needs no
# elevation; only the privileged helper does. WATTSON_PACKAGE_APP_DIR is an
# internal packaging-only destination and is accepted only under the temp root.
set -euo pipefail

APP_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --app-only) APP_ONLY=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Wattson"
APP_VERSION="${WATTSON_APP_VERSION:-$(/usr/bin/tr -d '\r\n' < "$ROOT_DIR/VERSION")}"
SWIFT_TARGET="arm64-apple-macos12.0"
PACKAGE_APP_DIR="${WATTSON_PACKAGE_APP_DIR:-}"
PACKAGE_BUILD=0
SYSTEM_TEMP_ROOT="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)"
SYSTEM_TEMP_ROOT="$(cd -P -- "$SYSTEM_TEMP_ROOT" && pwd)"
if [[ -n "$PACKAGE_APP_DIR" ]]; then
    [[ "$APP_ONLY" == "1" ]] || { echo "packaging destination requires --app-only" >&2; exit 2; }
    [[ "$(/usr/bin/basename "$PACKAGE_APP_DIR")" == "Wattson.app" ]] \
        || { echo "invalid packaging app destination" >&2; exit 2; }
    package_parent="$(cd -P -- "$(/usr/bin/dirname "$PACKAGE_APP_DIR")" 2>/dev/null && pwd)" \
        || { echo "packaging app parent is missing" >&2; exit 2; }
    case "$package_parent/" in
        "$SYSTEM_TEMP_ROOT/"*) ;;
        *) echo "packaging app destination must be inside the temp root" >&2; exit 2 ;;
    esac
    APP_DIR="$PACKAGE_APP_DIR"
    PACKAGE_BUILD=1
else
    APP_DIR="$HOME/Applications/Wattson.app"
fi
APP_BUNDLE_ID="com.leoarrow.wattson"
CANONICAL_APP_DIR="/Applications/Wattson.app"
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

if [[ "$PACKAGE_BUILD" != "1" && ( -e "$CANONICAL_APP_DIR" || -L "$CANONICAL_APP_DIR" ) ]]; then
    echo "Refusing to create a second Wattson app while $CANONICAL_APP_DIR exists." >&2
    echo "Build and install the native PKG to update the canonical app instead." >&2
    exit 1
fi

APP_ENTITLEMENTS="$ROOT_DIR/BatteryPowerApp.entitlements"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/install.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/install.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
FINAL_APP_DIR="$APP_DIR"
APP_DIR="$BUILD_DIR/Wattson.app"
CANDIDATE_APP_DIR="$APP_DIR"
wattson_cleanup_add_app "$CANDIDATE_APP_DIR"
if [[ "$PACKAGE_BUILD" == "1" ]]; then
    SUPPORT_DIR="$BUILD_DIR/Application Support/Wattson"
fi

if [[ "$PACKAGE_BUILD" == "1" ]]; then
    echo "📦 Building ${APP_NAME} for packaging..."
else
    echo "📦 Installing ${APP_NAME}..."
fi

# Build and verify the candidate before stopping or replacing an installation.
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# 3. Build. Top-level statements live in main.swift; every other source is a
# plain module file.
wattson_run xcrun swiftc \
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

echo "  ✅ Info.plist"

# 5. Copy the application icon when present.
ICON_SRC="$ROOT_DIR/design/icon/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
    /usr/bin/sips -s format png "$ICON_SRC" \
        --out "$APP_DIR/Contents/Resources/AppIconSettings.png" >/dev/null
    echo "  ✅ Icon"
else
    echo "  ⚠️  No AppIcon.icns found, skipping icon"
fi
for logo_resource in AppLogoColor.png AppLogoClearLight.png AppLogoClearDark.png; do
    cp "$ROOT_DIR/design/icon/in-app-logo/$logo_resource" \
        "$APP_DIR/Contents/Resources/$logo_resource"
done
for dock_logo_resource in AppDockLogoColor.png AppDockLogoClearLight.png AppDockLogoClearDark.png; do
    cp "$ROOT_DIR/design/icon/dock-logo/$dock_logo_resource" \
        "$APP_DIR/Contents/Resources/$dock_logo_resource"
done

# 6. Sign and verify the candidate.
wattson_run codesign --force --sign - --entitlements "$APP_ENTITLEMENTS" "$APP_DIR" >/dev/null
echo "  ✅ Ad-hoc code signature"
wattson_run codesign --verify --deep --strict "$APP_DIR"
if [[ "$APP_ONLY" != "1" ]]; then
    HELPER_SCRATCH_PATH="$BUILD_DIR/swiftpm-helper"
    wattson_run /usr/bin/swift build \
        --package-path "$ROOT_DIR" \
        --scratch-path "$HELPER_SCRATCH_PATH" \
        --configuration release \
        --triple "$SWIFT_TARGET" \
        --product wattson-helper
    wattson_run /usr/bin/swift build \
        --package-path "$ROOT_DIR" \
        --scratch-path "$HELPER_SCRATCH_PATH" \
        --configuration release \
        --triple "$SWIFT_TARGET" \
        --product wattson-helper \
        --show-bin-path > "$BUILD_DIR/helper-bin-path"
    HELPER_BUILD="$(cat "$BUILD_DIR/helper-bin-path")/wattson-helper"
    [[ -f "$HELPER_BUILD" && ! -L "$HELPER_BUILD" ]] \
        || { echo "SwiftPM did not produce wattson-helper" >&2; exit 1; }
    wattson_run codesign --force --sign - --identifier "$HELPER_LABEL" "$HELPER_BUILD" >/dev/null
    wattson_run codesign --verify --strict "$HELPER_BUILD"
fi

# Recheck immediately before publication; a concurrent PKG install wins.
if [[ "$PACKAGE_BUILD" != "1" && ( -e "$CANONICAL_APP_DIR" || -L "$CANONICAL_APP_DIR" ) ]]; then
    echo "Refusing to replace a developer app while $CANONICAL_APP_DIR exists." >&2
    exit 1
fi
APP_DIR="$FINAL_APP_DIR"
if [[ -L "$APP_DIR" ]]; then
    echo "Refusing to replace a symlinked app destination." >&2
    exit 1
fi
if [[ -e "$APP_DIR" ]]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")"
    [[ "$existing_id" == "$APP_BUNDLE_ID" ]] || {
        echo "Refusing to replace an unrelated app bundle." >&2
        exit 1
    }
fi

# Remove retired installations only after the candidate passed verification.
# Unregister before deleting so LaunchServices does not keep a stale record.
if [[ "$PACKAGE_BUILD" != "1" ]]; then
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
    echo "  ✅ Removed the legacy Battery Power app"
fi

# Publish the verified app.
if [[ "$PACKAGE_BUILD" != "1" ]]; then
    wattson_stop_executable "$APP_DIR/Contents/MacOS/Wattson"
    if [ -d "$APP_DIR" ]; then
        "$LSREGISTER" -u "$APP_DIR" >/dev/null 2>&1 || true
    fi
fi
rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")" "$SUPPORT_DIR"
mv "$CANDIDATE_APP_DIR" "$APP_DIR"

touch "$APP_DIR"
if [[ "$PACKAGE_BUILD" != "1" ]]; then
    "$LSREGISTER" -f "$APP_DIR" >/dev/null
fi

# 7. Install the privileged helper. launchd wakes it on demand and it exits
# after five idle seconds.
if [ "$APP_ONLY" = "1" ]; then
    echo "  ⏭  Skipping the privileged helper (--app-only)"
    # -e, not -x: the helper is 544 root:wheel, so it is deliberately not
    # executable by the user running this script.
    if [[ "$PACKAGE_BUILD" != "1" && ! -e "$HELPER_BIN" ]]; then
        echo "  ⚠️  No helper at $HELPER_BIN — live SMC power and mode switching are unavailable."
        echo "     Run ./scripts/install.sh without --app-only to install it."
    fi
    if [[ "$PACKAGE_BUILD" == "1" ]]; then
        echo "✅ Packaging app build complete"
        exit 0
    fi
    echo ""
    echo "🎉 Done. Launch with: open \"$APP_DIR\""
    exit 0
fi
echo "  🔑 Installing the privileged helper (needs sudo once)"
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
echo "  ✅ Socket-activated helper installed"

echo ""
echo "🎉 Done. Launch with: open \"$APP_DIR\""
