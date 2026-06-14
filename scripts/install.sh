#!/bin/bash
# install.sh — Install 电池功率 as a macOS app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="电池功率"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
MONITOR_SCRIPT="$SCRIPT_DIR/../battery_monitor.py"
INSTALL_PATH="$HOME/.battery_monitor.py"

echo "📦 Installing ${APP_NAME}..."

# 1. Copy monitor script
cp "$MONITOR_SCRIPT" "$INSTALL_PATH"
echo "  ✅ Script → $INSTALL_PATH"

# 2. Recreate app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 3. Build native launcher. LaunchServices is more reliable with a Mach-O
# executable than with a shell script as CFBundleExecutable.
cat > "$APP_DIR/Contents/MacOS/applet.c" << 'EOF'
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>

int main(void) {
    const char *home = getenv("HOME");
    const char *pythons[] = {
        "/usr/local/bin/python3",
        "/usr/bin/python3",
        "/opt/homebrew/bin/python3",
        NULL
    };
    char script[1024];

    if (home == NULL || strlen(home) > 900) {
        return 1;
    }
    snprintf(script, sizeof(script), "%s/.battery_monitor.py", home);

    for (int i = 0; pythons[i] != NULL; i++) {
        if (access(pythons[i], X_OK) == 0) {
            execl(pythons[i], pythons[i], script, (char *)NULL);
            return 1;
        }
    }

    execl(
        "/usr/bin/osascript",
        "osascript",
        "-e",
        "display alert \"电池功率启动失败\" message \"未找到可用的 Python 3 + Tkinter 运行环境。\"",
        (char *)NULL
    );
    return 1;
}
EOF
cc "$APP_DIR/Contents/MacOS/applet.c" -o "$APP_DIR/Contents/MacOS/applet"
rm -f "$APP_DIR/Contents/MacOS/applet.c"
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
</dict>
</plist>
EOF
echo "  ✅ Info.plist"

# 5. Copy icon if available
ICON_SRC="$SCRIPT_DIR/../design/icon/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "  ✅ Icon → $APP_DIR/Contents/Resources/AppIcon.icns"
else
    echo "  ⚠️  No AppIcon.icns found, skipping icon"
fi

echo ""
echo "🎉 Done! Open from ~/Applications/${APP_NAME}.app"
echo "   Or run: open ~/Applications/${APP_NAME}.app"
