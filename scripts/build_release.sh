#!/bin/bash
# Build the universal Wattson application and privileged helper.
set -euo pipefail
umask 022

export COPYFILE_DISABLE=1
export LC_ALL=C
export ZERO_AR_DATE=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
MIN_MACOS_VERSION="12.0"
APP_NAME="Wattson"
HELPER_LABEL="com.leoarrow.wattson.helper"
BUILD_ROOT="$ROOT_DIR/.build/release"
SWIFTPM_BUILD_DIR="$BUILD_ROOT/swiftpm"
APP_DIR="$BUILD_ROOT/${APP_NAME}.app"
APP_EXECUTABLE="$APP_DIR/Contents/MacOS/$APP_NAME"
HELPER_EXECUTABLE="$BUILD_ROOT/$HELPER_LABEL"
BUILD_METADATA="$BUILD_ROOT/BUILD-METADATA.txt"

fail() {
    echo "build_release.sh: $*" >&2
    exit 1
}

[[ -f "$VERSION_FILE" ]] || fail "missing VERSION file"
APP_VERSION="$(/bin/cat "$VERSION_FILE")"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "VERSION must contain one semantic version (x.y.z)"
BUILD_NUMBER="${WATTSON_BUILD_NUMBER:-$APP_VERSION}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
    || fail "WATTSON_BUILD_NUMBER must contain one to three dot-separated integers"

[[ -f "$ROOT_DIR/Package.swift" ]] || fail "missing Package.swift"
[[ -f "$ROOT_DIR/Packaging/AppInfo.plist" ]] || fail "missing Packaging/AppInfo.plist"

/bin/rm -rf -- "$BUILD_ROOT"
/bin/mkdir -p "$BUILD_ROOT"

echo "Building Wattson $APP_VERSION ($BUILD_NUMBER) for arm64 and x86_64..."
/usr/bin/swift build \
    --package-path "$ROOT_DIR" \
    --scratch-path "$SWIFTPM_BUILD_DIR" \
    --configuration release \
    --arch arm64 \
    --arch x86_64

BIN_DIR="$(
    /usr/bin/swift build \
        --package-path "$ROOT_DIR" \
        --scratch-path "$SWIFTPM_BUILD_DIR" \
        --configuration release \
        --arch arm64 \
        --arch x86_64 \
        --show-bin-path
)"
BUILT_APP_EXECUTABLE="$BIN_DIR/Wattson"
BUILT_HELPER_EXECUTABLE="$BIN_DIR/wattson-helper"
[[ -x "$BUILT_APP_EXECUTABLE" ]] || fail "SwiftPM did not produce $BUILT_APP_EXECUTABLE"
[[ -x "$BUILT_HELPER_EXECUTABLE" ]] || fail "SwiftPM did not produce $BUILT_HELPER_EXECUTABLE"

verify_universal_binary() {
    local binary_path="$1"
    local architecture
    local build_info

    /usr/bin/xcrun lipo "$binary_path" -verify_arch arm64 x86_64 \
        || fail "binary is not universal (arm64 + x86_64): $binary_path"
    for architecture in arm64 x86_64; do
        build_info="$(/usr/bin/xcrun vtool -arch "$architecture" -show-build "$binary_path")"
        /usr/bin/grep -Eq "minos[[:space:]]+$MIN_MACOS_VERSION([[:space:]]|$)" <<< "$build_info" \
            || fail "$architecture slice does not target macOS $MIN_MACOS_VERSION: $binary_path"
    done
}

verify_universal_binary "$BUILT_APP_EXECUTABLE"
verify_universal_binary "$BUILT_HELPER_EXECUTABLE"

/bin/mkdir -p \
    "$APP_DIR/Contents/MacOS" \
    "$APP_DIR/Contents/Resources"
/usr/bin/ditto --noextattr --noqtn "$BUILT_APP_EXECUTABLE" "$APP_EXECUTABLE"
/usr/bin/ditto --noextattr --noqtn "$BUILT_HELPER_EXECUTABLE" "$HELPER_EXECUTABLE"
/bin/cp "$ROOT_DIR/Packaging/AppInfo.plist" "$APP_DIR/Contents/Info.plist"
/bin/cp "$ROOT_DIR/design/icon/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
/usr/bin/sips -s format png "$ROOT_DIR/design/icon/AppIcon.icns" \
    --out "$APP_DIR/Contents/Resources/AppIconSettings.png" >/dev/null
/usr/bin/plutil -replace CFBundleShortVersionString -string "$APP_VERSION" \
    "$APP_DIR/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$BUILD_NUMBER" \
    "$APP_DIR/Contents/Info.plist"
/usr/bin/plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
/bin/chmod 755 "$APP_EXECUTABLE" "$HELPER_EXECUTABLE"
/usr/bin/xattr -cr "$APP_DIR" "$HELPER_EXECUTABLE"

APP_SIGN_IDENTITY="${WATTSON_DEVELOPER_ID_APP:-}"
if [[ -n "$APP_SIGN_IDENTITY" && "$APP_SIGN_IDENTITY" != "-" ]]; then
    SIGNING_MODE="developer-id"
    SIGN_ARGUMENTS=(
        --force
        --timestamp
        --options runtime
        --sign "$APP_SIGN_IDENTITY"
    )
else
    SIGNING_MODE="ad-hoc"
    SIGN_ARGUMENTS=(--force --sign -)
fi

/usr/bin/codesign \
    "${SIGN_ARGUMENTS[@]}" \
    --identifier "$HELPER_LABEL" \
    "$HELPER_EXECUTABLE"
/usr/bin/codesign \
    "${SIGN_ARGUMENTS[@]}" \
    --entitlements "$ROOT_DIR/BatteryPowerApp.entitlements" \
    "$APP_DIR"
/usr/bin/codesign --verify --strict "$HELPER_EXECUTABLE"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

{
    printf 'version=%s\n' "$APP_VERSION"
    printf 'build_number=%s\n' "$BUILD_NUMBER"
    printf 'architectures=arm64,x86_64\n'
    printf 'minimum_macos=%s\n' "$MIN_MACOS_VERSION"
    printf 'app_signature=%s\n' "$SIGNING_MODE"
    printf 'helper_signature=%s\n' "$SIGNING_MODE"
} > "$BUILD_METADATA"

echo "Built universal app: $APP_DIR"
echo "Built universal helper: $HELPER_EXECUTABLE"
if [[ "$SIGNING_MODE" == "ad-hoc" ]]; then
    echo "Signing: ad-hoc community build (not notarized)"
else
    echo "Signing: Developer ID application identity configured"
    echo "Notarization status: no (build_release.sh does not submit artifacts)"
fi
