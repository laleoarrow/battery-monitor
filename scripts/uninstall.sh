#!/bin/bash
# Remove Wattson v3, its v2 user-local predecessor, and privileged helper.
set -euo pipefail

readonly APP_DIR="/Applications/Wattson.app"
readonly LEGACY_APP_DIR="$HOME/Applications/Wattson.app"
readonly HELPER_LABEL="com.leoarrow.wattson.helper"
readonly HELPER_TARGET="system/$HELPER_LABEL"
readonly HELPER_PLIST="/Library/LaunchDaemons/${HELPER_LABEL}.plist"
readonly HELPER_BIN="/Library/PrivilegedHelperTools/${HELPER_LABEL}"
readonly HELPER_SOCKET="/var/run/wattson-helper.sock"
readonly LOGIN_AGENT_LABEL="com.leoarrow.wattson.login"
readonly LOGIN_AGENT_PLIST="$HOME/Library/LaunchAgents/${LOGIN_AGENT_LABEL}.plist"
LOGIN_AGENT_TARGET="gui/$(/usr/bin/id -u)/${LOGIN_AGENT_LABEL}"
readonly LOGIN_AGENT_TARGET
readonly PACKAGE_RECEIPT="com.leoarrow.wattson.pkg"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

run_as_root() {
    if [[ "$(/usr/bin/id -u)" == "0" ]]; then
        "$@"
    else
        /usr/bin/sudo "$@"
    fi
}

echo "Removing Wattson..."

/bin/launchctl bootout "$LOGIN_AGENT_TARGET" >/dev/null 2>&1 || true
/bin/rm -f -- "$LOGIN_AGENT_PLIST"

/usr/bin/pkill -f '^/Applications/Wattson\.app/Contents/MacOS/Wattson([[:space:]]|$)' \
    >/dev/null 2>&1 || true
/usr/bin/pkill -f "$LEGACY_APP_DIR/Contents/MacOS/Wattson" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$APP_DIR" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$LEGACY_APP_DIR" >/dev/null 2>&1 || true

if [[ -e "$HELPER_PLIST" || -L "$HELPER_PLIST" \
    || -e "$HELPER_BIN" || -L "$HELPER_BIN" \
    || -e "$HELPER_SOCKET" || -L "$HELPER_SOCKET" \
    || -e "$APP_DIR" || -L "$APP_DIR" ]] \
    || /usr/sbin/pkgutil --pkg-info "$PACKAGE_RECEIPT" >/dev/null 2>&1; then
    echo "Administrator approval is required to remove the system installation."
    run_as_root /bin/launchctl bootout "$HELPER_TARGET" >/dev/null 2>&1 || true
    run_as_root /bin/launchctl enable "$HELPER_TARGET" >/dev/null 2>&1 || true
    run_as_root /bin/rm -f -- "$HELPER_SOCKET" "$HELPER_PLIST" "$HELPER_BIN"
    run_as_root /bin/rm -rf -- "$APP_DIR"
    run_as_root /usr/sbin/pkgutil --forget "$PACKAGE_RECEIPT" >/dev/null 2>&1 || true
fi

/bin/rm -rf -- "$LEGACY_APP_DIR"

echo "Wattson was removed. Settings remain in ~/Library/Application Support/Wattson."
