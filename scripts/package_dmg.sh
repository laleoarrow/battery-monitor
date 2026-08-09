#!/bin/bash
# Wrap the exact native installer PKG in a read-only distribution DMG.
set -euo pipefail
umask 022

export COPYFILE_DISABLE=1
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_NAME="Wattson"
DIST_DIR="$ROOT_DIR/dist"

fail() {
    echo "package_dmg.sh: $*" >&2
    exit 1
}

[[ -f "$VERSION_FILE" ]] || fail "missing VERSION file"
APP_VERSION="$(/bin/cat "$VERSION_FILE")"
REQUESTED_VERSION="${1:-$APP_VERSION}"
[[ "$REQUESTED_VERSION" == "$APP_VERSION" ]] \
    || fail "requested version $REQUESTED_VERSION does not match VERSION ($APP_VERSION)"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid VERSION"

PKG_NAME="${APP_NAME}-v${APP_VERSION}-macos-universal.pkg"
DMG_NAME="${APP_NAME}-v${APP_VERSION}-macos-universal.dmg"
PKG_PATH="$DIST_DIR/$PKG_NAME"
DMG_PATH="$DIST_DIR/$DMG_NAME"
[[ -f "$PKG_PATH" && ! -L "$PKG_PATH" ]] \
    || fail "missing $PKG_PATH; run scripts/package_pkg.sh first"
/usr/sbin/pkgutil --payload-files "$PKG_PATH" >/dev/null \
    || fail "input is not a readable flat package: $PKG_PATH"

SYSTEM_TEMP_ROOT="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)"
SYSTEM_TEMP_ROOT="$(cd -P -- "$SYSTEM_TEMP_ROOT" && pwd)"
STAGING_DIR="$(/usr/bin/mktemp -d "$SYSTEM_TEMP_ROOT/wattson-dmg.XXXXXX")"

cleanup() {
    /bin/rm -rf -- "$STAGING_DIR"
}
trap cleanup EXIT

/bin/cp "$PKG_PATH" "$STAGING_DIR/$PKG_NAME"
/usr/bin/cmp -s "$PKG_PATH" "$STAGING_DIR/$PKG_NAME" \
    || fail "staged PKG does not match the release PKG"
/usr/bin/touch "$STAGING_DIR/.metadata_never_index"
/bin/chmod 644 "$STAGING_DIR/$PKG_NAME" "$STAGING_DIR/.metadata_never_index"
/bin/chmod 755 "$STAGING_DIR"
/bin/chmod -R a+rX "$STAGING_DIR"

/bin/rm -f -- "$DMG_PATH"
/usr/bin/hdiutil create \
    -volname "Wattson $APP_VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" >/dev/null

APP_SIGN_IDENTITY="${WATTSON_DEVELOPER_ID_APP:-}"
if [[ -n "$APP_SIGN_IDENTITY" && "$APP_SIGN_IDENTITY" != "-" ]]; then
    /usr/bin/codesign \
        --force \
        --timestamp \
        --sign "$APP_SIGN_IDENTITY" \
        "$DMG_PATH"
    /usr/bin/codesign --verify --strict "$DMG_PATH"
    DMG_SIGNING_MODE="developer-id"
else
    DMG_SIGNING_MODE="unsigned"
fi

/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null
WATTSON_EXPECT_DMG_SIGNED="$([[ "$DMG_SIGNING_MODE" == "developer-id" ]] && echo 1 || echo 0)" \
    /bin/bash "$SCRIPT_DIR/verify_dmg.sh" "$DMG_PATH" "$PKG_PATH"

echo "Created $DMG_SIGNING_MODE DMG: $DMG_PATH"
if [[ "${WATTSON_RELEASE_ORCHESTRATED:-0}" == "1" ]]; then
    echo "Notarization/checksums: pending release orchestration"
else
    echo "Notarization status: no (use scripts/release.sh with WATTSON_NOTARIZE=1)"
    /usr/bin/shasum -a 256 "$DMG_PATH"
fi
