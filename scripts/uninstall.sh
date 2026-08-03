#!/bin/bash
# uninstall.sh — Remove Wattson and its privileged helper
set -euo pipefail

APP_DIR="$HOME/Applications/Wattson.app"
HELPER_LABEL="com.leoarrow.wattson.helper"
HELPER_PLIST="/Library/LaunchDaemons/${HELPER_LABEL}.plist"
HELPER_BIN="/Library/PrivilegedHelperTools/${HELPER_LABEL}"
LOGIN_AGENT_LABEL="com.leoarrow.wattson.login"
LOGIN_AGENT_PLIST="$HOME/Library/LaunchAgents/${LOGIN_AGENT_LABEL}.plist"
LOGIN_AGENT_TARGET="gui/$(id -u)/${LOGIN_AGENT_LABEL}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "🧹 Removing Wattson..."

launchctl bootout "$LOGIN_AGENT_TARGET" >/dev/null 2>&1 || true
rm -f "$LOGIN_AGENT_PLIST"
echo "  ✅ Login item removed"

pkill -f "$APP_DIR/Contents/MacOS/Wattson" 2>/dev/null || true
"$LSREGISTER" -u "$APP_DIR" >/dev/null 2>&1 || true
rm -rf "$APP_DIR"
echo "  ✅ App removed"

if [ -f "$HELPER_PLIST" ] || [ -f "$HELPER_BIN" ]; then
    echo "  🔑 Removing the privileged helper needs sudo"
    sudo launchctl bootout system "$HELPER_PLIST" 2>/dev/null || true
    sudo rm -f "$HELPER_PLIST" "$HELPER_BIN" /var/run/wattson-helper.sock
    echo "  ✅ Helper removed"
fi

echo "  ℹ️  Settings kept at ~/Library/Application Support/Wattson (delete manually if unwanted)"
echo "✅ Done"
