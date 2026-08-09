#!/bin/bash
# Headless structural verification for release builds and packaged artifacts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_ROOT="$ROOT_DIR/.build/release"
APP_DIR="$BUILD_ROOT/Wattson.app"
APP_EXECUTABLE="$APP_DIR/Contents/MacOS/Wattson"
HELPER_LABEL="com.leoarrow.wattson.helper"
HELPER_EXECUTABLE="$BUILD_ROOT/$HELPER_LABEL"
BUILD_METADATA="$BUILD_ROOT/BUILD-METADATA.txt"
MIN_MACOS_VERSION="12.0"

fail() {
    echo "verify_release.sh: $*" >&2
    exit 1
}

verify_binary() {
    local binary_path="$1"
    local architectures
    local architecture
    local build_info

    [[ -f "$binary_path" && ! -L "$binary_path" ]] \
        || fail "missing binary: $binary_path"
    /usr/bin/xcrun lipo "$binary_path" -verify_arch arm64 x86_64 \
        || fail "binary is missing a required architecture: $binary_path"
    architectures="$(/usr/bin/xcrun lipo -archs "$binary_path")"
    [[ "$(/usr/bin/wc -w <<< "$architectures" | /usr/bin/tr -d ' ')" == "2" ]] \
        || fail "binary contains unexpected architectures: $architectures"
    for architecture in arm64 x86_64; do
        build_info="$(/usr/bin/xcrun vtool -arch "$architecture" -show-build "$binary_path")"
        /usr/bin/grep -Eq "minos[[:space:]]+$MIN_MACOS_VERSION([[:space:]]|$)" <<< "$build_info" \
            || fail "$architecture slice has the wrong deployment target: $binary_path"
    done
}

[[ -f "$VERSION_FILE" ]] || fail "missing VERSION file"
APP_VERSION="$(/bin/cat "$VERSION_FILE")"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid VERSION"
[[ -d "$APP_DIR" && ! -L "$APP_DIR" ]] || fail "missing release app"
/usr/bin/plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")" == "com.leoarrow.wattson" ]] \
    || fail "wrong app bundle identifier"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")" == "$APP_VERSION" ]] \
    || fail "app version does not match VERSION"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_DIR/Contents/Info.plist")" == "$MIN_MACOS_VERSION" ]] \
    || fail "Info.plist has the wrong minimum macOS version"
if /usr/bin/find "$APP_DIR/Contents/Resources" -name InfoPlist.strings -print -quit \
    | /usr/bin/grep -q .; then
    fail "release app must keep the Wattson name in every locale"
fi

verify_binary "$APP_EXECUTABLE"
verify_binary "$HELPER_EXECUTABLE"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
/usr/bin/codesign --verify --strict "$HELPER_EXECUTABLE"
[[ -f "$BUILD_METADATA" ]]
/usr/bin/grep -Fxq "version=$APP_VERSION" "$BUILD_METADATA"
/usr/bin/grep -Fxq "architectures=arm64,x86_64" "$BUILD_METADATA"
/usr/bin/grep -Fxq "minimum_macos=$MIN_MACOS_VERSION" "$BUILD_METADATA"

if [[ "${1:-}" == "--build-only" ]]; then
    [[ "$#" == "1" ]] || fail "--build-only does not accept artifact paths"
    echo "Verified universal release build for Wattson $APP_VERSION"
    exit 0
fi
if [[ "$#" != "2" ]]; then
    echo "usage: $0 --build-only | /path/to/Wattson.pkg /path/to/Wattson.dmg" >&2
    exit 2
fi

PKG_PATH="$1"
DMG_PATH="$2"
[[ -f "$PKG_PATH" && ! -L "$PKG_PATH" ]] || fail "missing PKG: $PKG_PATH"
[[ -f "$DMG_PATH" && ! -L "$DMG_PATH" ]] || fail "missing DMG: $DMG_PATH"
[[ "$(/usr/bin/basename "$PKG_PATH")" == "Wattson-v${APP_VERSION}-macos-universal.pkg" ]] \
    || fail "unexpected PKG filename"
[[ "$(/usr/bin/basename "$DMG_PATH")" == "Wattson-v${APP_VERSION}-macos-universal.dmg" ]] \
    || fail "unexpected DMG filename"

PAYLOAD_FILES="$(
    /usr/sbin/pkgutil --payload-files "$PKG_PATH" \
        | /usr/bin/sed 's#^\./##'
)"
for payload_path in \
    "Applications/Wattson.app/Contents/MacOS/Wattson" \
    "Library/PrivilegedHelperTools/$HELPER_LABEL" \
    "Library/LaunchDaemons/$HELPER_LABEL.plist"; do
    /usr/bin/grep -Fxq "$payload_path" <<< "$PAYLOAD_FILES" \
        || fail "PKG is missing $payload_path"
done

EXPAND_BASE="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/wattson-pkg-expand.XXXXXX")"
EXPAND_DIR="$EXPAND_BASE/expanded"
cleanup() {
    /bin/rm -rf -- "$EXPAND_BASE"
}
trap cleanup EXIT
/usr/sbin/pkgutil --expand-full "$PKG_PATH" "$EXPAND_DIR"
[[ -n "$(/usr/bin/find "$EXPAND_DIR" -type f -name preinstall -print -quit)" ]] \
    || fail "PKG is missing preinstall"
[[ -n "$(/usr/bin/find "$EXPAND_DIR" -type f -name postinstall -print -quit)" ]] \
    || fail "PKG is missing postinstall"

if [[ "${WATTSON_EXPECT_INSTALLER_SIGNED:-0}" == "1" ]]; then
    /usr/sbin/pkgutil --check-signature "$PKG_PATH"
fi
if [[ "${WATTSON_EXPECT_NOTARIZED:-0}" == "1" ]]; then
    /usr/bin/xcrun stapler validate -v "$PKG_PATH"
    /usr/bin/xcrun stapler validate -v "$DMG_PATH"
fi

/bin/bash "$SCRIPT_DIR/verify_dmg.sh" "$DMG_PATH" "$PKG_PATH"
echo "Verified Wattson $APP_VERSION PKG and byte-identical DMG wrapper"
