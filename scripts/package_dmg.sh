#!/bin/bash
# package_dmg.sh - Build a drag-to-Applications DMG for 电池功率
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="电池功率"
APP_VERSION="${1:-1.3.0}"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/${APP_NAME}-v${APP_VERSION}.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/battery-dmg.XXXXXX")"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo "📦 Building ${APP_NAME} v${APP_VERSION}..."
pkill -f "${APP_DIR}/Contents/MacOS/applet" >/dev/null 2>&1 || true
bash "$SCRIPT_DIR/install.sh"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

ditto "$APP_DIR" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "${APP_NAME} v${APP_VERSION}" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "✅ DMG → $DMG_PATH"
shasum -a 256 "$DMG_PATH"
