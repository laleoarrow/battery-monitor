#!/bin/bash
# package_dmg.sh - Build a self-contained installer DMG for Wattson
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Wattson"
APP_VERSION="${1:-2.0.0}"
SWIFT_TARGET="arm64-apple-macos12.0"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
HELPER_LABEL="com.leoarrow.wattson.helper"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/${APP_NAME}-v${APP_VERSION}.dmg"

if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)?$ ]]; then
    echo "invalid version: $APP_VERSION" >&2
    exit 2
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wattson-dmg.XXXXXX")"
SUPPORT_DIR="$STAGING_DIR/.wattson-support"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo "📦 Building ${APP_NAME} v${APP_VERSION}..."
pkill -f "${APP_DIR}/Contents/MacOS/Wattson" >/dev/null 2>&1 || true
WATTSON_APP_VERSION="$APP_VERSION" bash "$SCRIPT_DIR/install.sh" --app-only

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

ditto "$APP_DIR" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

# Ship the privileged helper alongside the app so recipients can enable every
# control without needing this source repository or Xcode.
mkdir -p "$SUPPORT_DIR"
xcrun swiftc "$ROOT_DIR/Helper/wattson-helper.swift" \
    -target "$SWIFT_TARGET" \
    -O \
    -o "$SUPPORT_DIR/$HELPER_LABEL"
codesign --force --sign - "$SUPPORT_DIR/$HELPER_LABEL" >/dev/null
cp "$ROOT_DIR/Helper/${HELPER_LABEL}.plist" "$SUPPORT_DIR/${HELPER_LABEL}.plist"

cat > "$STAGING_DIR/Install Wattson.command" << 'INSTALLER'
#!/bin/bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SOURCE="$SOURCE_DIR/Wattson.app"
SUPPORT_SOURCE="$SOURCE_DIR/.wattson-support"
APP_DEST="$HOME/Applications/Wattson.app"
HELPER_LABEL="com.leoarrow.wattson.helper"
HELPER_DEST="/Library/PrivilegedHelperTools/$HELPER_LABEL"
PLIST_DEST="/Library/LaunchDaemons/${HELPER_LABEL}.plist"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

verify_payload() {
    test -d "$APP_SOURCE"
    test -f "$SUPPORT_SOURCE/$HELPER_LABEL"
    test -f "$SUPPORT_SOURCE/${HELPER_LABEL}.plist"
    codesign --verify --deep --strict "$APP_SOURCE"
    codesign --verify --strict "$SUPPORT_SOURCE/$HELPER_LABEL"
    plutil -lint "$SUPPORT_SOURCE/${HELPER_LABEL}.plist" >/dev/null
}

verify_payload
if [ "${1:-}" = "--verify" ]; then
    echo "Wattson installer payload verified."
    exit 0
fi

echo "Installing Wattson..."
mkdir -p "$HOME/Applications"
pkill -f "$APP_DEST/Contents/MacOS/Wattson" >/dev/null 2>&1 || true
if [ -d "$APP_DEST" ]; then
    "$LSREGISTER" -u "$APP_DEST" >/dev/null 2>&1 || true
fi
rm -rf "$APP_DEST"
ditto "$APP_SOURCE" "$APP_DEST"
# The user has already approved this private test build by opening this
# installer. Remove quarantine only from the verified copy we just installed.
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
touch "$APP_DEST"
"$LSREGISTER" -f "$APP_DEST" >/dev/null

echo "Installing the optional power-control helper (macOS will ask for an administrator password)..."
sudo launchctl bootout system "$PLIST_DEST" >/dev/null 2>&1 || true
sudo install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
sudo install -o root -g wheel -m 544 "$SUPPORT_SOURCE/$HELPER_LABEL" "$HELPER_DEST"
sudo install -o root -g wheel -m 644 "$SUPPORT_SOURCE/${HELPER_LABEL}.plist" "$PLIST_DEST"
sudo launchctl bootstrap system "$PLIST_DEST"

open "$APP_DEST"
echo "Wattson is installed and running from $APP_DEST"
INSTALLER
chmod +x "$STAGING_DIR/Install Wattson.command"

cat > "$STAGING_DIR/Quick Start.txt" << GUIDE
WATTSON v${APP_VERSION} — QUICK START

PRIVATE TEST BUILD
This build is ad-hoc signed and is not Apple-notarized. Install it only if you
trust the sender. Keep Gatekeeper enabled; use right-click → Open when macOS asks.

FULL INSTALLATION
1. Double-click “Install Wattson.command”.
2. Enter your Mac administrator password when Terminal asks.
3. Wattson launches automatically in the menu bar.

If macOS blocks the installer, right-click “Install Wattson.command” and choose Open.

MONITOR-ONLY INSTALLATION
Drag Wattson.app to Applications. Live monitoring works, but power-mode switching
and system battery-icon controls require the full installer above.

USING WATTSON
• Left-click the menu-bar battery icon to open the live power monitor.
• Right-click the icon for a quick power-mode toggle.
• Drag the Liquid Glass control to Automatic, Low Power, or High Power
  (High Power appears only on supported Macs).

SYSTEM REQUIREMENTS
Apple silicon Mac with a built-in battery, macOS 12 or later.

PRIVACY
Wattson reads battery and power status locally. No account, analytics, or upload.

ASK CODEX TO INSTALL
“Install Wattson from this mounted DMG. First run ‘Install Wattson.command --verify’,
then run the installer. Preserve unrelated files, launch Wattson, and verify its
menu-bar icon and popover. Pause for me when macOS asks for a password or approval.”
GUIDE

hdiutil create \
    -volname "${APP_NAME} v${APP_VERSION}" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "✅ DMG → $DMG_PATH"
shasum -a 256 "$DMG_PATH"
