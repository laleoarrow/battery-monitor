#!/bin/bash
# package_dmg.sh - Build a single-action graphical installer DMG for Wattson
set -euo pipefail
umask 022

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Wattson"
APP_VERSION="${1:-2.0.3}"
SWIFT_TARGET="arm64-apple-macos12.0"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
HELPER_LABEL="com.leoarrow.wattson.helper"
INSTALLER_NAME="Install Wattson.app"
INSTALLER_EXECUTABLE="Install Wattson"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/${APP_NAME}-v${APP_VERSION}.dmg"

if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)?$ ]]; then
    echo "invalid version: $APP_VERSION" >&2
    exit 2
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wattson-dmg.XXXXXX")"
INSTALLER_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wattson-installer-build.XXXXXX")"
chmod 755 "$STAGING_DIR"
INSTALLER_DIR="$STAGING_DIR/$INSTALLER_NAME"
INSTALLER_CONTENTS="$INSTALLER_DIR/Contents"
INSTALLER_MACOS="$INSTALLER_CONTENTS/MacOS"
INSTALLER_RESOURCES="$INSTALLER_CONTENTS/Resources"
PAYLOAD_DIR="$INSTALLER_RESOURCES/Payload"

cleanup() {
    rm -rf "$STAGING_DIR" "$INSTALLER_BUILD_DIR"
}
trap cleanup EXIT

echo "📦 Building ${APP_NAME} v${APP_VERSION}..."
pkill -f "${APP_DIR}/Contents/MacOS/Wattson" >/dev/null 2>&1 || true
WATTSON_APP_VERSION="$APP_VERSION" bash "$SCRIPT_DIR/install.sh" --app-only

mkdir -p "$DIST_DIR" "$INSTALLER_MACOS" "$PAYLOAD_DIR"
rm -f "$DMG_PATH"

# Keep the shipping app inside an archive so Spotlight and LaunchServices do
# not register a second Wattson while the read-only image is mounted.
ditto -c -k --sequesterRsrc --keepParent \
    "$APP_DIR" \
    "$PAYLOAD_DIR/Wattson.zip"

# The graphical installer deploys the existing fixed-command helper after the
# user approves the standard macOS administrator prompt.
xcrun swiftc "$ROOT_DIR/Helper/wattson-helper.swift" \
    -target "$SWIFT_TARGET" \
    -O \
    -o "$PAYLOAD_DIR/$HELPER_LABEL"
codesign --force --sign - "$PAYLOAD_DIR/$HELPER_LABEL" >/dev/null
cp "$ROOT_DIR/Helper/${HELPER_LABEL}.plist" "$PAYLOAD_DIR/${HELPER_LABEL}.plist"
cp "$ROOT_DIR/Installer/install-helper.sh" "$INSTALLER_RESOURCES/install-helper.sh"
chmod 755 "$INSTALLER_RESOURCES/install-helper.sh"

WATTSON_ARCHIVE_SHA256="$(shasum -a 256 "$PAYLOAD_DIR/Wattson.zip" | awk '{print $1}')"
INSTALL_HELPER_SHA256="$(shasum -a 256 "$INSTALLER_RESOURCES/install-helper.sh" | awk '{print $1}')"
HELPER_BINARY_SHA256="$(shasum -a 256 "$PAYLOAD_DIR/$HELPER_LABEL" | awk '{print $1}')"
HELPER_PLIST_SHA256="$(shasum -a 256 "$PAYLOAD_DIR/${HELPER_LABEL}.plist" | awk '{print $1}')"

sed \
    -e "s/__WATTSON_ARCHIVE_SHA256__/$WATTSON_ARCHIVE_SHA256/g" \
    -e "s/__INSTALL_HELPER_SHA256__/$INSTALL_HELPER_SHA256/g" \
    -e "s/__HELPER_BINARY_SHA256__/$HELPER_BINARY_SHA256/g" \
    -e "s/__HELPER_PLIST_SHA256__/$HELPER_PLIST_SHA256/g" \
    "$ROOT_DIR/Installer/main.swift" > "$INSTALLER_BUILD_DIR/main.swift"
if grep -Eq '__[A-Z_]+SHA256__' "$INSTALLER_BUILD_DIR/main.swift"; then
    echo "installer payload hash substitution failed" >&2
    exit 1
fi

xcrun swiftc \
    "$INSTALLER_BUILD_DIR/main.swift" \
    -target "$SWIFT_TARGET" \
    -framework AppKit \
    -O \
    -o "$INSTALLER_MACOS/$INSTALLER_EXECUTABLE"

cat > "$INSTALLER_CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Install Wattson</string>
    <key>CFBundleDisplayName</key>
    <string>Install Wattson</string>
    <key>CFBundleIdentifier</key>
    <string>com.leoarrow.wattson.installer</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${INSTALLER_EXECUTABLE}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

cp "$ROOT_DIR/design/icon/AppIcon.icns" "$INSTALLER_RESOURCES/AppIcon.icns"
codesign --force --sign - "$INSTALLER_DIR" >/dev/null
codesign --verify --deep --strict "$INSTALLER_DIR"

# mktemp creates its directory as 0700. If that mode reaches the image, other
# users can see the icons but cannot open them. Normalize every shipped path.
touch "$STAGING_DIR/.metadata_never_index"
chmod -R a+rX "$STAGING_DIR"
chmod 755 "$STAGING_DIR"

hdiutil create \
    -volname "${APP_NAME} v${APP_VERSION}" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

hdiutil verify "$DMG_PATH" >/dev/null
bash "$SCRIPT_DIR/verify_dmg.sh" "$DMG_PATH"
echo "✅ DMG → $DMG_PATH"
shasum -a 256 "$DMG_PATH"
