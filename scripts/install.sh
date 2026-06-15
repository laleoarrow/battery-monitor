#!/bin/bash
# install.sh — Install 电池功率 as a macOS app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="电池功率"
APP_VERSION="1.1.1"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
MONITOR_SCRIPT="$SCRIPT_DIR/../battery_monitor.py"
SWIFT_SOURCE="$SCRIPT_DIR/../BatteryPowerWidget.swift"
WIDGET_SOURCE="$SCRIPT_DIR/../BatteryPowerWidgetExtension.swift"
INSTALL_PATH="$HOME/.battery_monitor.py"
WIDGET_NAME="BatteryPowerWidgetExtension"
WIDGET_BUNDLE_ID="com.leoarrow.battery-monitor.widget"
WIDGET_DIR="$APP_DIR/Contents/PlugIns/${WIDGET_NAME}.appex"
WIDGET_ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/battery-widget-entitlements.XXXXXX.plist")"
trap 'rm -f "$WIDGET_ENTITLEMENTS"' EXIT

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

# 4. Build WidgetKit extension for the macOS widget gallery.
mkdir -p "$WIDGET_DIR/Contents/MacOS"
WIDGET_TARGET="$(uname -m)-apple-macosx14.0"
xcrun swiftc "$WIDGET_SOURCE" \
    -parse-as-library \
    -application-extension \
    -target "$WIDGET_TARGET" \
    -framework WidgetKit \
    -framework SwiftUI \
    -framework AppIntents \
    -o "$WIDGET_DIR/Contents/MacOS/$WIDGET_NAME"
chmod +x "$WIDGET_DIR/Contents/MacOS/$WIDGET_NAME"
cat > "$WIDGET_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${WIDGET_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${WIDGET_BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${WIDGET_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
EOF
cat > "$WIDGET_ENTITLEMENTS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
    <array>
        <string>/Library/Application Support/电池功率/</string>
    </array>
</dict>
</plist>
EOF
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
