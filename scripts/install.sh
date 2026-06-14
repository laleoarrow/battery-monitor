#!/bin/bash
# install.sh — Install 电池功率 as a macOS app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="电池功率"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
MONITOR_SCRIPT="$SCRIPT_DIR/battery_monitor.py"
INSTALL_PATH="$HOME/.battery_monitor.py"

echo "📦 Installing ${APP_NAME}..."

# 1. Copy monitor script
cp "$MONITOR_SCRIPT" "$INSTALL_PATH"
echo "  ✅ Script → $INSTALL_PATH"

# 2. Create app bundle structure
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 3. Write launcher
cat > "$APP_DIR/Contents/MacOS/applet" << 'EOF'
#!/bin/bash
exec /usr/local/bin/python3 "$HOME/.battery_monitor.py"
EOF
chmod +x "$APP_DIR/Contents/MacOS/applet"
echo "  ✅ Launcher → $APP_DIR/Contents/MacOS/applet"

# 4. Write Info.plist
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
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>applet</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
</dict>
</plist>
EOF
echo "  ✅ Info.plist"

# 5. Copy icon if available
ICON_SRC="$SCRIPT_DIR/design/icon/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "  ✅ Icon → $APP_DIR/Contents/Resources/AppIcon.icns"
else
    echo "  ⚠️  No AppIcon.icns found, skipping icon"
fi

echo ""
echo "🎉 Done! Open from ~/Applications/${APP_NAME}.app"
echo "   Or run: open ~/Applications/${APP_NAME}.app"
