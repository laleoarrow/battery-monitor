#!/bin/bash
# Build the standalone, read-only Wattson Diagnostics support app.
set -euo pipefail
umask 022

export COPYFILE_DISABLE=1
export LC_ALL=C

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "$0")" && /bin/pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_PATH="$ROOT_DIR/Support/WattsonDiagnostics/main.swift"
HELPER_CLIENT_SOURCE="$ROOT_DIR/Core/HelperClient.swift"
DIAGNOSTICS_VERSION="1.1.0"
MIN_MACOS_VERSION="12.0"
APP_NAME="Wattson Diagnostics"
BUNDLE_ID="com.leoarrow.wattson.diagnostics"
BUILD_ROOT="$ROOT_DIR/.build/diagnostics"
APP_DIR="$BUILD_ROOT/${APP_NAME}.app"
EXECUTABLE_PATH="$APP_DIR/Contents/MacOS/$APP_NAME"
DIST_DIR="$ROOT_DIR/dist/support"
ZIP_NAME="Wattson-Diagnostics-v${DIAGNOSTICS_VERSION}-macos-universal.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
INFO_NAME="Wattson-Diagnostics-v${DIAGNOSTICS_VERSION}-release-info.txt"
INFO_PATH="$DIST_DIR/$INFO_NAME"
CHECKSUM_PATH="$DIST_DIR/SHA256SUMS.txt"
ARCHIVE_VERIFY_ROOT="$BUILD_ROOT/archive-verify"

fail() {
    echo "build_diagnostics.sh: $*" >&2
    exit 1
}

[[ -f "$SOURCE_PATH" ]] || fail "missing diagnostics source"
[[ -f "$HELPER_CLIENT_SOURCE" ]] || fail "missing helper client source"
[[ -f "$ROOT_DIR/design/icon/AppIcon.icns" ]] || fail "missing AppIcon.icns"

/bin/rm -rf -- "$BUILD_ROOT"
/bin/mkdir -p "$BUILD_ROOT/arm64" "$BUILD_ROOT/x86_64" "$DIST_DIR"
/bin/rm -f -- "$ZIP_PATH" "$INFO_PATH" "$CHECKSUM_PATH"

for architecture in arm64 x86_64; do
    /usr/bin/xcrun swiftc \
        "$SOURCE_PATH" \
        "$HELPER_CLIENT_SOURCE" \
        -target "${architecture}-apple-macos${MIN_MACOS_VERSION}" \
        -framework AppKit \
        -framework IOKit \
        -O \
        -o "$BUILD_ROOT/$architecture/$APP_NAME"
done

/bin/mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/usr/bin/xcrun lipo -create \
    "$BUILD_ROOT/arm64/$APP_NAME" \
    "$BUILD_ROOT/x86_64/$APP_NAME" \
    -output "$EXECUTABLE_PATH"
/bin/chmod 755 "$EXECUTABLE_PATH"
/bin/cp "$ROOT_DIR/design/icon/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

/bin/cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${DIAGNOSTICS_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${DIAGNOSTICS_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

/usr/bin/plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
/usr/bin/xattr -cr "$APP_DIR"
/usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
/usr/bin/xcrun lipo "$EXECUTABLE_PATH" -verify_arch arm64 x86_64 \
    || fail "diagnostics executable is not universal"
"$EXECUTABLE_PATH" --host-redaction-self-test \
    || fail "diagnostics hostname redaction self-test failed"
for architecture in arm64 x86_64; do
    build_info="$(/usr/bin/xcrun vtool -arch "$architecture" -show-build "$EXECUTABLE_PATH")"
    /usr/bin/grep -Eq "minos[[:space:]]+$MIN_MACOS_VERSION([[:space:]]|$)" <<< "$build_info" \
        || fail "$architecture slice does not target macOS $MIN_MACOS_VERSION"
done

(
    cd "$BUILD_ROOT"
    /usr/bin/ditto -c -k \
        --norsrc --noextattr --noqtn --noacl --keepParent \
        "${APP_NAME}.app" "$ZIP_PATH"
)
/usr/bin/unzip -t "$ZIP_PATH" >/dev/null
/bin/mkdir -p "$ARCHIVE_VERIFY_ROOT"
/usr/bin/unzip -q "$ZIP_PATH" -d "$ARCHIVE_VERIFY_ROOT"
EXTRACTED_APP="$ARCHIVE_VERIFY_ROOT/${APP_NAME}.app"
[[ -d "$EXTRACTED_APP" ]] || fail "archive does not contain the diagnostics app"
if /usr/bin/find "$EXTRACTED_APP" -name '._*' -print -quit | /usr/bin/grep -q .; then
    fail "archive contains AppleDouble metadata inside the app bundle"
fi
/usr/bin/codesign --verify --deep --strict "$EXTRACTED_APP"
/usr/bin/xcrun lipo "$EXTRACTED_APP/Contents/MacOS/$APP_NAME" \
    -verify_arch arm64 x86_64 \
    || fail "extracted diagnostics executable is not universal"

{
    printf 'name=Wattson Diagnostics\n'
    printf 'version=%s\n' "$DIAGNOSTICS_VERSION"
    printf 'architectures=arm64,x86_64\n'
    printf 'minimum_macos=%s\n' "$MIN_MACOS_VERSION"
    printf 'signature=ad-hoc\n'
    printf 'notarized=no\n'
    printf 'privilege=none\n'
    printf 'network_upload=none\n'
} > "$INFO_PATH"

(
    cd "$DIST_DIR"
    /usr/bin/shasum -a 256 "$ZIP_NAME" "$INFO_NAME" > "$CHECKSUM_PATH"
    /usr/bin/shasum -a 256 -c "$(/usr/bin/basename "$CHECKSUM_PATH")"
)

echo "Built: $APP_DIR"
echo "Archive: $ZIP_PATH"
echo "Checksums: $CHECKSUM_PATH"
