#!/bin/bash
# install.sh — Install 电池功率 as a macOS app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="电池功率"
APP_VERSION="1.2.0"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
MONITOR_SCRIPT="$SCRIPT_DIR/../battery_monitor.py"
SWIFT_SOURCE="$SCRIPT_DIR/../BatteryPowerWidget.swift"
WIDGET_PROJECT="$SCRIPT_DIR/../BatteryPowerWidgetExtension.xcodeproj"
INSTALL_PATH="$HOME/.battery_monitor.py"
WIDGET_NAME="BatteryPowerWidgetExtension"
WIDGET_BUNDLE_ID="com.leoarrow.battery-monitor.widget"
WIDGET_DIR="$APP_DIR/Contents/PlugIns/${WIDGET_NAME}.appex"
APP_ENTITLEMENTS="$SCRIPT_DIR/../BatteryPowerApp.entitlements"
WIDGET_ENTITLEMENTS="$SCRIPT_DIR/../BatteryPowerWidgetExtension.entitlements"
WIDGET_BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/battery-widget-build.XXXXXX")"
cleanup() {
    rm -rf "$WIDGET_BUILD_ROOT"
}
trap cleanup EXIT

echo "📦 Installing ${APP_NAME}..."

# 1. Copy monitor script
cp "$MONITOR_SCRIPT" "$INSTALL_PATH"
echo "  ✅ Script → $INSTALL_PATH"

# 2. Recreate app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/PlugIns"

# 3. Build native AppKit executable. Tk windows remain rectangular at the
# window layer; the native panel gives true transparent rounded corners.
xcrun swiftc "$SWIFT_SOURCE" \
    -framework AppKit \
    -framework CoreGraphics \
    -o "$APP_DIR/Contents/MacOS/applet"
chmod +x "$APP_DIR/Contents/MacOS/applet"
echo "  ✅ Native app → $APP_DIR/Contents/MacOS/applet"

# 4. Build WidgetKit extension for the macOS widget gallery. Xcode must build
# this target so WidgetKit gets the app-extension entry point it expects.
xcrun xcodebuild \
    -project "$WIDGET_PROJECT" \
    -scheme "$WIDGET_NAME" \
    -configuration Release \
    -derivedDataPath "$WIDGET_BUILD_ROOT" \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null
BUILT_WIDGET="$WIDGET_BUILD_ROOT/Build/Products/Release/${WIDGET_NAME}.appex"
if [ ! -d "$BUILT_WIDGET" ]; then
    echo "  ❌ WidgetKit extension build product not found: $BUILT_WIDGET"
    exit 1
fi
rm -rf "$WIDGET_DIR"
cp -R "$BUILT_WIDGET" "$WIDGET_DIR"
echo "  ✅ WidgetKit extension → $WIDGET_DIR"

# 5. Write Info.plist
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
    <string>com.leoarrow.battery-monitor</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>applet</string>
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

# 6. Copy icon if available
ICON_SRC="$SCRIPT_DIR/../design/icon/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "  ✅ Icon → $APP_DIR/Contents/Resources/AppIcon.icns"
else
    echo "  ⚠️  No AppIcon.icns found, skipping icon"
fi

codesign --force --sign - --entitlements "$WIDGET_ENTITLEMENTS" "$WIDGET_DIR" >/dev/null
codesign --force --sign - --entitlements "$APP_ENTITLEMENTS" "$APP_DIR" >/dev/null
codesign --force --deep --sign - --preserve-metadata=entitlements "$APP_DIR" >/dev/null
echo "  ✅ Ad-hoc code signature"

if xcrun pluginkit -a "$WIDGET_DIR" >/dev/null 2>&1; then
    echo "  ✅ WidgetKit extension registered"
else
    echo "  ⚠️  WidgetKit extension built; macOS may index it after opening the app"
fi

echo ""
echo "🎉 Done! Open from ~/Applications/${APP_NAME}.app"
echo "   Or run: open ~/Applications/${APP_NAME}.app"
