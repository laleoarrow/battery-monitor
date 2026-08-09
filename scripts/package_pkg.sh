#!/bin/bash
# Create a native macOS installer package from the verified release build.
set -euo pipefail
umask 022

export COPYFILE_DISABLE=1
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_NAME="Wattson"
HELPER_LABEL="com.leoarrow.wattson.helper"
BUILD_ROOT="$ROOT_DIR/.build/release"
APP_DIR="$BUILD_ROOT/${APP_NAME}.app"
HELPER_EXECUTABLE="$BUILD_ROOT/$HELPER_LABEL"
BUILD_METADATA="$BUILD_ROOT/BUILD-METADATA.txt"
DIST_DIR="$ROOT_DIR/dist"
COMPONENT_ID="com.leoarrow.wattson.pkg"
PRODUCT_ID="com.leoarrow.wattson.installer"
PACKAGE_SCRIPTS="$ROOT_DIR/Packaging/pkg"
COMPONENT_PLIST="$PACKAGE_SCRIPTS/component.plist"

fail() {
    echo "package_pkg.sh: $*" >&2
    exit 1
}

[[ -f "$VERSION_FILE" ]] || fail "missing VERSION file"
APP_VERSION="$(/bin/cat "$VERSION_FILE")"
REQUESTED_VERSION="${1:-$APP_VERSION}"
[[ "$REQUESTED_VERSION" == "$APP_VERSION" ]] \
    || fail "requested version $REQUESTED_VERSION does not match VERSION ($APP_VERSION)"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid VERSION"

FINAL_PKG="$DIST_DIR/${APP_NAME}-v${APP_VERSION}-macos-universal.pkg"
[[ -d "$APP_DIR" && ! -L "$APP_DIR" ]] \
    || fail "missing release app; run scripts/build_release.sh first"
[[ -f "$HELPER_EXECUTABLE" && ! -L "$HELPER_EXECUTABLE" ]] \
    || fail "missing release helper; run scripts/build_release.sh first"
[[ -f "$BUILD_METADATA" ]] || fail "missing release build metadata"
[[ "$(/usr/bin/grep '^version=' "$BUILD_METADATA")" == "version=$APP_VERSION" ]] \
    || fail "release build metadata does not match VERSION"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")" == "$APP_VERSION" ]] \
    || fail "release app version does not match VERSION"
/usr/bin/xcrun lipo "$APP_DIR/Contents/MacOS/Wattson" -verify_arch arm64 x86_64 \
    || fail "release app is not universal"
/usr/bin/xcrun lipo "$HELPER_EXECUTABLE" -verify_arch arm64 x86_64 \
    || fail "release helper is not universal"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
/usr/bin/codesign --verify --strict "$HELPER_EXECUTABLE"

SYSTEM_TEMP_ROOT="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)"
SYSTEM_TEMP_ROOT="$(cd -P -- "$SYSTEM_TEMP_ROOT" && pwd)"
PKG_WORK_DIR="$(/usr/bin/mktemp -d "$SYSTEM_TEMP_ROOT/wattson-pkg.XXXXXX")"
PKG_ROOT="$PKG_WORK_DIR/root"
COMPONENT_PKG="$PKG_WORK_DIR/Wattson-component.pkg"

cleanup() {
    /bin/rm -rf -- "$PKG_WORK_DIR"
}
trap cleanup EXIT

/bin/mkdir -p \
    "$PKG_ROOT/Applications" \
    "$PKG_ROOT/Library/PrivilegedHelperTools" \
    "$PKG_ROOT/Library/LaunchDaemons" \
    "$DIST_DIR"
/usr/bin/ditto --noextattr --noqtn "$APP_DIR" "$PKG_ROOT/Applications/Wattson.app"
/usr/bin/install -m 755 \
    "$HELPER_EXECUTABLE" \
    "$PKG_ROOT/Library/PrivilegedHelperTools/$HELPER_LABEL"
/usr/bin/install -m 644 \
    "$ROOT_DIR/Helper/$HELPER_LABEL.plist" \
    "$PKG_ROOT/Library/LaunchDaemons/$HELPER_LABEL.plist"
/usr/bin/xattr -cr "$PKG_ROOT"
/bin/chmod 544 "$PKG_ROOT/Library/PrivilegedHelperTools/$HELPER_LABEL"

for installer_script in preinstall postinstall; do
    [[ -x "$PACKAGE_SCRIPTS/$installer_script" ]] \
        || fail "$PACKAGE_SCRIPTS/$installer_script must be executable"
    /bin/bash -n "$PACKAGE_SCRIPTS/$installer_script"
done
/usr/bin/plutil -lint "$COMPONENT_PLIST" >/dev/null

/usr/bin/pkgbuild \
    --root "$PKG_ROOT" \
    --scripts "$PACKAGE_SCRIPTS" \
    --component-plist "$COMPONENT_PLIST" \
    --identifier "$COMPONENT_ID" \
    --version "$APP_VERSION" \
    --install-location / \
    --ownership recommended \
    "$COMPONENT_PKG"

PRODUCTBUILD_ARGUMENTS=(
    --package "$COMPONENT_PKG"
    --identifier "$PRODUCT_ID"
    --version "$APP_VERSION"
)
INSTALLER_IDENTITY="${WATTSON_DEVELOPER_ID_INSTALLER:-}"
if [[ -n "$INSTALLER_IDENTITY" && "$INSTALLER_IDENTITY" != "-" ]]; then
    PRODUCTBUILD_ARGUMENTS+=(--sign "$INSTALLER_IDENTITY")
    PACKAGE_SIGNING_MODE="developer-id"
else
    PACKAGE_SIGNING_MODE="unsigned"
fi

/bin/rm -f -- "$FINAL_PKG"
/usr/bin/productbuild "${PRODUCTBUILD_ARGUMENTS[@]}" "$FINAL_PKG"
[[ -f "$FINAL_PKG" ]] || fail "productbuild did not create $FINAL_PKG"

PAYLOAD_FILES="$(
    /usr/sbin/pkgutil --payload-files "$FINAL_PKG" \
        | /usr/bin/sed 's#^\./##'
)"
/usr/bin/grep -Fxq "Applications/Wattson.app/Contents/MacOS/Wattson" <<< "$PAYLOAD_FILES" \
    || fail "package is missing the canonical app payload"
/usr/bin/grep -Fxq "Library/PrivilegedHelperTools/$HELPER_LABEL" <<< "$PAYLOAD_FILES" \
    || fail "package is missing the helper payload"
/usr/bin/grep -Fxq "Library/LaunchDaemons/$HELPER_LABEL.plist" <<< "$PAYLOAD_FILES" \
    || fail "package is missing the LaunchDaemon payload"

if [[ "$PACKAGE_SIGNING_MODE" == "developer-id" ]]; then
    /usr/sbin/pkgutil --check-signature "$FINAL_PKG"
    echo "Created Developer ID-signed PKG: $FINAL_PKG"
    echo "Notarization status: no (use scripts/release.sh with WATTSON_NOTARIZE=1)"
else
    echo "Created unsigned community PKG: $FINAL_PKG"
    echo "Notarization status: no (Developer ID Installer identity is not configured)"
fi
