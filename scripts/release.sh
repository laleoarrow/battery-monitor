#!/bin/bash
# Build, package, optionally notarize, verify, and checksum one Wattson release.
set -euo pipefail
umask 022

export COPYFILE_DISABLE=1
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
DIST_DIR="$ROOT_DIR/dist"

fail() {
    echo "release.sh: $*" >&2
    exit 1
}

[[ -f "$VERSION_FILE" ]] || fail "missing VERSION file"
APP_VERSION="$(/bin/cat "$VERSION_FILE")"
REQUESTED_VERSION="${1:-$APP_VERSION}"
[[ "$REQUESTED_VERSION" == "$APP_VERSION" ]] \
    || fail "requested version $REQUESTED_VERSION does not match VERSION ($APP_VERSION)"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid VERSION"

NOTARIZE_RELEASE="${WATTSON_NOTARIZE:-0}"
[[ "$NOTARIZE_RELEASE" == "0" || "$NOTARIZE_RELEASE" == "1" ]] \
    || fail "WATTSON_NOTARIZE must be 0 or 1"

APP_IDENTITY="${WATTSON_DEVELOPER_ID_APP:-}"
INSTALLER_IDENTITY="${WATTSON_DEVELOPER_ID_INSTALLER:-}"
if [[ "$APP_IDENTITY" == "-" ]]; then
    APP_IDENTITY=""
fi
if [[ "$INSTALLER_IDENTITY" == "-" ]]; then
    INSTALLER_IDENTITY=""
fi
if [[ -n "$APP_IDENTITY" && -z "$INSTALLER_IDENTITY" ]] \
    || [[ -z "$APP_IDENTITY" && -n "$INSTALLER_IDENTITY" ]]; then
    fail "configure both Developer ID Application and Installer identities, or neither"
fi

if [[ -n "$APP_IDENTITY" ]]; then
    DISTRIBUTION_MODE="developer-id"
    APP_SIGNATURE="developer-id"
    HELPER_SIGNATURE="developer-id"
    PACKAGE_SIGNATURE="developer-id"
    DMG_SIGNATURE="developer-id"
    EXPECT_SIGNED=1
else
    DISTRIBUTION_MODE="community-ad-hoc"
    APP_SIGNATURE="ad-hoc"
    HELPER_SIGNATURE="ad-hoc"
    PACKAGE_SIGNATURE="unsigned"
    DMG_SIGNATURE="unsigned"
    EXPECT_SIGNED=0
fi

if [[ "$NOTARIZE_RELEASE" == "1" ]]; then
    [[ "$DISTRIBUTION_MODE" == "developer-id" ]] \
        || fail "notarization requires both Developer ID identities"
    if [[ -z "${WATTSON_NOTARY_KEYCHAIN_PROFILE:-}" ]] \
        && [[ -z "${WATTSON_NOTARY_KEY_PATH:-}" \
            || -z "${WATTSON_NOTARY_KEY_ID:-}" \
            || -z "${WATTSON_NOTARY_ISSUER:-}" ]]; then
        fail "notarization credentials are not configured"
    fi
fi

PKG_NAME="Wattson-v${APP_VERSION}-macos-universal.pkg"
DMG_NAME="Wattson-v${APP_VERSION}-macos-universal.dmg"
PKG_PATH="$DIST_DIR/$PKG_NAME"
DMG_PATH="$DIST_DIR/$DMG_NAME"
RELEASE_INFO_NAME="Wattson-v${APP_VERSION}-release-info.txt"
RELEASE_INFO_PATH="$DIST_DIR/$RELEASE_INFO_NAME"
CHECKSUM_PATH="$DIST_DIR/SHA256SUMS.txt"

/bin/mkdir -p "$DIST_DIR"
/bin/rm -f -- "$PKG_PATH" "$DMG_PATH" "$RELEASE_INFO_PATH" "$CHECKSUM_PATH"

echo "Release mode: $DISTRIBUTION_MODE"
if [[ "$NOTARIZE_RELEASE" == "0" ]]; then
    echo "Notarization requested: no"
fi

/bin/bash "$SCRIPT_DIR/build_release.sh"
/bin/bash "$SCRIPT_DIR/verify_release.sh" --build-only
/bin/bash "$SCRIPT_DIR/package_pkg.sh" "$APP_VERSION"

if [[ "$NOTARIZE_RELEASE" == "1" ]]; then
    /bin/bash "$SCRIPT_DIR/notarize.sh" "$PKG_PATH"
fi

WATTSON_RELEASE_ORCHESTRATED=1 \
    /bin/bash "$SCRIPT_DIR/package_dmg.sh" "$APP_VERSION"

if [[ "$NOTARIZE_RELEASE" == "1" ]]; then
    /bin/bash "$SCRIPT_DIR/notarize.sh" "$DMG_PATH"
    NOTARIZED="yes"
    STAPLED="yes"
else
    NOTARIZED="no"
    STAPLED="no"
fi

WATTSON_EXPECT_INSTALLER_SIGNED="$EXPECT_SIGNED" \
WATTSON_EXPECT_DMG_SIGNED="$EXPECT_SIGNED" \
WATTSON_EXPECT_NOTARIZED="$NOTARIZE_RELEASE" \
    /bin/bash "$SCRIPT_DIR/verify_release.sh" "$PKG_PATH" "$DMG_PATH"

BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$ROOT_DIR/.build/release/Wattson.app/Contents/Info.plist")"
{
    printf 'version=%s\n' "$APP_VERSION"
    printf 'build_number=%s\n' "$BUILD_NUMBER"
    printf 'architectures=arm64,x86_64\n'
    printf 'minimum_macos=12.0\n'
    printf 'install_path=/Applications/Wattson.app\n'
    printf 'helper_path=/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper\n'
    printf 'distribution_mode=%s\n' "$DISTRIBUTION_MODE"
    printf 'app_signature=%s\n' "$APP_SIGNATURE"
    printf 'helper_signature=%s\n' "$HELPER_SIGNATURE"
    printf 'package_signature=%s\n' "$PACKAGE_SIGNATURE"
    printf 'dmg_signature=%s\n' "$DMG_SIGNATURE"
    printf 'notarized=%s\n' "$NOTARIZED"
    printf 'stapled=%s\n' "$STAPLED"
} > "$RELEASE_INFO_PATH"

(
    cd "$DIST_DIR"
    /usr/bin/shasum -a 256 "$PKG_NAME"
    /usr/bin/shasum -a 256 "$DMG_NAME"
    /usr/bin/shasum -a 256 "$RELEASE_INFO_NAME"
) > "$CHECKSUM_PATH"
(
    cd "$DIST_DIR"
    /usr/bin/shasum -a 256 -c "$(/usr/bin/basename "$CHECKSUM_PATH")"
)

echo "Created release artifacts in $DIST_DIR"
echo "Notarized: $NOTARIZED"
echo "Checksums: $CHECKSUM_PATH"
