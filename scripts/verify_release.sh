#!/bin/bash
# Headless structural verification for release builds and packaged artifacts.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_ROOT="$ROOT_DIR/.build/release"
APP_DIR="$BUILD_ROOT/Wattson.app"
APP_EXECUTABLE="$APP_DIR/Contents/MacOS/Wattson"
HELPER_LABEL="com.leoarrow.wattson.helper"
HELPER_EXECUTABLE="$BUILD_ROOT/$HELPER_LABEL"
BUILD_METADATA="$BUILD_ROOT/BUILD-METADATA.txt"
APP_ENTITLEMENTS="$ROOT_DIR/BatteryPowerApp.entitlements"
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

verify_v5_protocol_surface() {
    local app_executable="$1"
    local helper_executable="$2"

    /usr/bin/strings "$app_executable" \
        | /usr/bin/grep -F -- "--helper-v5-observation-probe" >/dev/null \
        || fail "release app is missing the strict helper v5 probe"
    /usr/bin/strings "$helper_executable" \
        | /usr/bin/grep -F -- "getPowerObservation" >/dev/null \
        || fail "release helper is missing the v5 observation operation"
}

verify_app_bundle() {
    local app_dir="$1"

    [[ -d "$app_dir" && ! -L "$app_dir" ]] || fail "missing release app: $app_dir"
    /usr/bin/plutil -lint "$app_dir/Contents/Info.plist" >/dev/null
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_dir/Contents/Info.plist")" == "com.leoarrow.wattson" ]] \
        || fail "wrong app bundle identifier: $app_dir"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")" == "$APP_VERSION" ]] \
        || fail "app version does not match VERSION: $app_dir"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app_dir/Contents/Info.plist")" == "$MIN_MACOS_VERSION" ]] \
        || fail "Info.plist has the wrong minimum macOS version: $app_dir"
    if /usr/bin/find "$app_dir/Contents/Resources" -name InfoPlist.strings -print -quit \
        | /usr/bin/grep -q .; then
        fail "release app must keep the Wattson name in every locale: $app_dir"
    fi
}

verify_expected_team_id() {
    local signing_details="$1"
    local artifact_name="$2"
    local team_identifier
    local team_identifier_count

    team_identifier_count="$(/usr/bin/grep -c '^TeamIdentifier=' <<< "$signing_details" || true)"
    [[ "$team_identifier_count" == "1" ]] \
        || fail "$artifact_name signature must contain exactly one TeamIdentifier"
    team_identifier="$(/usr/bin/sed -n 's/^TeamIdentifier=//p' <<< "$signing_details")"
    [[ -n "$team_identifier" && "$team_identifier" != "not set" ]] \
        || fail "$artifact_name signature is missing a Developer ID TeamIdentifier"
    if [[ -n "$EXPECTED_TEAM_ID" && "$team_identifier" != "$EXPECTED_TEAM_ID" ]]; then
        fail "$artifact_name TeamIdentifier is $team_identifier, expected $EXPECTED_TEAM_ID"
    fi
    if [[ -z "$SIGNED_RELEASE_TEAM_ID" ]]; then
        SIGNED_RELEASE_TEAM_ID="$team_identifier"
    elif [[ "$team_identifier" != "$SIGNED_RELEASE_TEAM_ID" ]]; then
        fail "$artifact_name TeamIdentifier does not match the other release signatures"
    fi
}

verify_developer_id_application_signature() {
    local signed_path="$1"
    local artifact_name="$2"
    local expect_runtime="$3"
    local signing_details
    local leaf_authority
    local timestamp_line

    /usr/bin/codesign --verify --strict "$signed_path" \
        || fail "$artifact_name code signature is invalid"
    signing_details="$(/usr/bin/codesign --display --verbose=4 "$signed_path" 2>&1)" \
        || fail "could not read $artifact_name code signature"
    leaf_authority="$(/usr/bin/sed -n '/^Authority=/{p;q;}' <<< "$signing_details")"
    [[ "$leaf_authority" == "Authority=Developer ID Application: "* ]] \
        || fail "$artifact_name leaf authority is not Developer ID Application"

    verify_expected_team_id "$signing_details" "$artifact_name"
    [[ "$leaf_authority" == *" ($SIGNED_RELEASE_TEAM_ID)" ]] \
        || fail "$artifact_name leaf authority does not match its TeamIdentifier"

    timestamp_line="$(/usr/bin/sed -n '/^Timestamp=/p' <<< "$signing_details")"
    [[ -n "$timestamp_line" && "$timestamp_line" != "Timestamp=none" ]] \
        || fail "$artifact_name is missing a secure timestamp"
    if [[ "$expect_runtime" == "1" ]]; then
        /usr/bin/grep -Eq '^CodeDirectory .*flags=.*\([^)]*runtime[^)]*\)' <<< "$signing_details" \
            || fail "$artifact_name is missing the hardened runtime flag"
    fi
}

verify_production_entitlements() {
    local app_dir="$1"
    local helper_path="$2"
    local work_dir="$3"
    local actual_app_entitlements="$work_dir/app-entitlements.plist"
    local actual_helper_entitlements="$work_dir/helper-entitlements.plist"
    local canonical_expected_entitlements="$work_dir/expected-entitlements.json"
    local canonical_actual_entitlements="$work_dir/actual-entitlements.json"
    local entitlements_path

    /bin/mkdir -p "$work_dir"
    /usr/bin/codesign --display --entitlements :- "$app_dir" \
        > "$actual_app_entitlements" 2>/dev/null \
        || fail "could not extract packaged app entitlements"
    /usr/bin/codesign --display --entitlements :- "$helper_path" \
        > "$actual_helper_entitlements" 2>/dev/null \
        || fail "could not extract packaged helper entitlements"
    /usr/bin/plutil -lint "$actual_app_entitlements" >/dev/null \
        || fail "packaged app entitlements are not a property list"

    for entitlements_path in \
        "$APP_ENTITLEMENTS" \
        "$actual_app_entitlements" \
        "$actual_helper_entitlements"; do
        if /usr/bin/grep -Fq 'com.apple.security.get-task-allow' "$entitlements_path"; then
            fail "production signatures must not contain com.apple.security.get-task-allow"
        fi
    done

    # Reserializing both plists avoids comparing XML formatting or dictionary key order.
    /usr/bin/plutil -convert json \
        -o "$canonical_expected_entitlements" "$APP_ENTITLEMENTS"
    /usr/bin/plutil -convert json \
        -o "$canonical_actual_entitlements" "$actual_app_entitlements"
    /usr/bin/cmp -s \
        "$canonical_expected_entitlements" "$canonical_actual_entitlements" \
        || fail "packaged app entitlements do not match BatteryPowerApp.entitlements"
}

verify_installer_signature() {
    local pkg_path="$1"
    local signature_details
    local installer_authority

    if ! signature_details="$(/usr/sbin/pkgutil --check-signature "$pkg_path" 2>&1)"; then
        /bin/echo "$signature_details" >&2
        fail "PKG signature is invalid"
    fi
    /usr/bin/grep -Fq 'Signed with a trusted timestamp on:' <<< "$signature_details" \
        || fail "PKG is missing a trusted installer timestamp"

    installer_authority="$(/usr/bin/sed -nE 's/^[[:space:]]*1\. //p' <<< "$signature_details")"
    [[ "$installer_authority" == "Developer ID Installer: "* ]] \
        || fail "PKG leaf authority is not Developer ID Installer"
    [[ "$installer_authority" == *" ($SIGNED_RELEASE_TEAM_ID)" ]] \
        || fail "PKG Installer authority does not match the app TeamIdentifier"
}

verify_gatekeeper() {
    local artifact_path="$1"
    local assessment_type="$2"
    local artifact_name="$3"
    local assessment_output

    if ! assessment_output="$(
        /usr/sbin/spctl --assess --type "$assessment_type" --verbose=4 "$artifact_path" 2>&1
    )"; then
        /bin/echo "$assessment_output" >&2
        fail "Gatekeeper rejected $artifact_name"
    fi
}

verify_dmg_gatekeeper() {
    local dmg_path="$1"
    local assessment_output

    if ! assessment_output="$(
        /usr/sbin/spctl \
            --assess \
            --type open \
            --context context:primary-signature \
            --verbose=4 \
            "$dmg_path" 2>&1
    )"; then
        /bin/echo "$assessment_output" >&2
        fail "Gatekeeper rejected DMG"
    fi
}

[[ -f "$VERSION_FILE" ]] || fail "missing VERSION file"
[[ -f "$APP_ENTITLEMENTS" ]] || fail "missing BatteryPowerApp.entitlements"
APP_VERSION="$(/bin/cat "$VERSION_FILE")"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid VERSION"
EXPECT_INSTALLER_SIGNED="${WATTSON_EXPECT_INSTALLER_SIGNED:-0}"
EXPECT_DMG_SIGNED="${WATTSON_EXPECT_DMG_SIGNED:-0}"
EXPECT_NOTARIZED="${WATTSON_EXPECT_NOTARIZED:-0}"
EXPECTED_TEAM_ID="${WATTSON_EXPECT_TEAM_ID:-}"
[[ "$EXPECT_INSTALLER_SIGNED" == "0" || "$EXPECT_INSTALLER_SIGNED" == "1" ]] \
    || fail "WATTSON_EXPECT_INSTALLER_SIGNED must be 0 or 1"
[[ "$EXPECT_DMG_SIGNED" == "0" || "$EXPECT_DMG_SIGNED" == "1" ]] \
    || fail "WATTSON_EXPECT_DMG_SIGNED must be 0 or 1"
[[ "$EXPECT_NOTARIZED" == "0" || "$EXPECT_NOTARIZED" == "1" ]] \
    || fail "WATTSON_EXPECT_NOTARIZED must be 0 or 1"
if [[ -n "$EXPECTED_TEAM_ID" && ! "$EXPECTED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    fail "WATTSON_EXPECT_TEAM_ID must be a 10-character uppercase Team ID"
fi
SIGNED_RELEASE_REQUIRED=0
if [[ "$EXPECT_INSTALLER_SIGNED" == "1" || "$EXPECT_DMG_SIGNED" == "1" ]]; then
    SIGNED_RELEASE_REQUIRED=1
fi
SIGNED_RELEASE_TEAM_ID=""

verify_app_bundle "$APP_DIR"

verify_binary "$APP_EXECUTABLE"
verify_binary "$HELPER_EXECUTABLE"
verify_v5_protocol_surface "$APP_EXECUTABLE" "$HELPER_EXECUTABLE"
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

PACKAGED_APP_DIR="$(
    /usr/bin/find "$EXPAND_DIR" \
        -type d \
        -path '*/Payload/Applications/Wattson.app' \
        -print
)"
[[ -n "$PACKAGED_APP_DIR" ]] || fail "expanded PKG is missing the Wattson app"
[[ "$(/usr/bin/wc -l <<< "$PACKAGED_APP_DIR" | /usr/bin/tr -d ' ')" == "1" ]] \
    || fail "expanded PKG contains multiple Wattson app payloads"
PACKAGED_HELPER_EXECUTABLE="$(
    /usr/bin/find "$EXPAND_DIR" \
        -type f \
        -path "*/Payload/Library/PrivilegedHelperTools/$HELPER_LABEL" \
        -print
)"
[[ -n "$PACKAGED_HELPER_EXECUTABLE" ]] || fail "expanded PKG is missing the helper"
[[ "$(/usr/bin/wc -l <<< "$PACKAGED_HELPER_EXECUTABLE" | /usr/bin/tr -d ' ')" == "1" ]] \
    || fail "expanded PKG contains multiple helper payloads"
PACKAGED_APP_EXECUTABLE="$PACKAGED_APP_DIR/Contents/MacOS/Wattson"

verify_app_bundle "$PACKAGED_APP_DIR"
verify_binary "$PACKAGED_APP_EXECUTABLE"
verify_binary "$PACKAGED_HELPER_EXECUTABLE"
verify_v5_protocol_surface "$PACKAGED_APP_EXECUTABLE" "$PACKAGED_HELPER_EXECUTABLE"
/usr/bin/codesign --verify --deep --strict "$PACKAGED_APP_DIR"
/usr/bin/codesign --verify --strict "$PACKAGED_HELPER_EXECUTABLE"

if [[ "$SIGNED_RELEASE_REQUIRED" == "1" ]]; then
    verify_developer_id_application_signature \
        "$PACKAGED_APP_DIR" "packaged app" 1
    verify_developer_id_application_signature \
        "$PACKAGED_HELPER_EXECUTABLE" "packaged helper" 1
    verify_production_entitlements \
        "$PACKAGED_APP_DIR" \
        "$PACKAGED_HELPER_EXECUTABLE" \
        "$EXPAND_BASE/signing-verification"
    verify_gatekeeper "$PACKAGED_APP_DIR" execute "packaged app"
fi
if [[ "$EXPECT_INSTALLER_SIGNED" == "1" ]]; then
    verify_installer_signature "$PKG_PATH"
    verify_gatekeeper "$PKG_PATH" install "PKG"
fi
if [[ "$EXPECT_DMG_SIGNED" == "1" ]]; then
    verify_developer_id_application_signature "$DMG_PATH" "DMG" 0
    verify_dmg_gatekeeper "$DMG_PATH"
fi
if [[ "$EXPECT_NOTARIZED" == "1" ]]; then
    /usr/bin/xcrun stapler validate -v "$PKG_PATH"
    /usr/bin/xcrun stapler validate -v "$DMG_PATH"
fi

/bin/bash "$SCRIPT_DIR/verify_dmg.sh" "$DMG_PATH" "$PKG_PATH"
echo "Verified Wattson $APP_VERSION PKG and byte-identical DMG wrapper"
