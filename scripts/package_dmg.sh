#!/bin/bash
# Package the same release app for helper-free drag-to-Applications monitoring.
set -euo pipefail
umask 022

export COPYFILE_DISABLE=1
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/local_cleanup.sh"
wattson_cleanup_init
VERSION_FILE="$ROOT_DIR/VERSION"
APP_NAME="Wattson"
DIST_DIR="${WATTSON_RELEASE_DIST_DIR:-$ROOT_DIR/dist}"
BUILD_ROOT="${WATTSON_RELEASE_BUILD_ROOT:-$ROOT_DIR/.build/release}"
APP_DIR="$BUILD_ROOT/$APP_NAME.app"

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

DMG_NAME="${APP_NAME}-v${APP_VERSION}-macos-universal.dmg"
OUTPUT_DMG="$DIST_DIR/$DMG_NAME"
[[ -d "$APP_DIR" && ! -L "$APP_DIR" ]] \
    || fail "missing $APP_DIR; run scripts/build_release.sh first"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")" == "$APP_VERSION" ]] \
    || fail "release app version does not match VERSION"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
/bin/mkdir -p "$DIST_DIR"

SCRATCH_PARENT="${WATTSON_RELEASE_BUILD_ROOT:-$ROOT_DIR/.build/local.noindex}"
/bin/mkdir -p "$SCRATCH_PARENT"
DMG_WORK_DIR="$(/usr/bin/mktemp -d "$SCRATCH_PARENT/dmg.XXXXXX")"
wattson_cleanup_add_dir "$DMG_WORK_DIR"
STAGING_DIR="$DMG_WORK_DIR/payload"
DMG_PATH="$DMG_WORK_DIR/$DMG_NAME"
/bin/mkdir -p "$STAGING_DIR"

wattson_run /usr/bin/ditto --noextattr --noqtn "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
/usr/bin/diff -qr "$APP_DIR" "$STAGING_DIR/$APP_NAME.app" \
    || fail "staged app does not match the release app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/touch "$STAGING_DIR/.metadata_never_index"
/bin/chmod 644 "$STAGING_DIR/.metadata_never_index"
/bin/chmod 755 "$STAGING_DIR"

wattson_run /usr/bin/hdiutil create \
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

wattson_run /usr/bin/hdiutil verify "$DMG_PATH" >/dev/null
WATTSON_EXPECT_DMG_SIGNED="$([[ "$DMG_SIGNING_MODE" == "developer-id" ]] && echo 1 || echo 0)" \
    wattson_run_script "$SCRIPT_DIR/verify_dmg.sh" "$DMG_PATH" "$APP_DIR"

/bin/mv -f -- "$DMG_PATH" "$OUTPUT_DMG"
DMG_PATH="$OUTPUT_DMG"
echo "Created $DMG_SIGNING_MODE DMG: $DMG_PATH"
if [[ "${WATTSON_RELEASE_ORCHESTRATED:-0}" == "1" ]]; then
    echo "Notarization/checksums: pending release orchestration"
else
    echo "Notarization status: no (use scripts/release.sh with WATTSON_NOTARIZE=1)"
    /usr/bin/shasum -a 256 "$DMG_PATH"
fi
