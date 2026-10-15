#!/bin/bash
# Build the isolated QA app and run its defaults-only CLI check. By default
# all app bundles are removed afterward; --keep-app explicitly hands off the
# verified bundle for a later visual review. This never opens UI.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW_ROOT="$ROOT_DIR/.build/preview.noindex"
APP_BUNDLE="$PREVIEW_ROOT/Wattson Glass Preview.app"
PREVIEW_ID="com.leoarrow.wattson.glass-preview"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
KEEP_APP=0

if [[ $# -eq 1 && "$1" == --keep-app ]]; then
    KEEP_APP=1
elif [[ $# -ne 0 ]]; then
    echo "usage: $0 [--keep-app] (headless verification; cleans up by default)" >&2
    exit 2
fi
if /usr/bin/pgrep -x WattsonGlassPreview >/dev/null; then
    echo "Close Wattson Glass Preview before rebuilding its bundle." >&2
    exit 2
fi
if [[ -L "$APP_BUNDLE" ]]; then
    echo "Refusing to replace a symlinked app bundle." >&2
    exit 2
fi
if [[ -e "$APP_BUNDLE" ]]; then
    EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
    [[ "$EXISTING_ID" == "$PREVIEW_ID" || "$EXISTING_ID" == "$PREVIEW_ID".* ]] || {
        echo "Refusing to replace an unrelated app bundle." >&2
        exit 2
    }
fi

mkdir -p "$PREVIEW_ROOT"
wattson_cleanup_init
if [[ "$KEEP_APP" == 0 ]]; then
    wattson_cleanup_add_app "$APP_BUNDLE"
    wattson_cleanup_add_dir "$APP_BUNDLE"
fi
BUILD_DIR="$(mktemp -d "$PREVIEW_ROOT/build.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
RUN_PREVIEW_ID="$PREVIEW_ID.$(/usr/bin/basename "$BUILD_DIR")"
wattson_cleanup_add_container "$RUN_PREVIEW_ID"
STAGED_APP="$BUILD_DIR/Wattson Glass Preview.app"
wattson_cleanup_add_app "$STAGED_APP"

wattson_run xcrun swiftc \
    "$ROOT_DIR"/Core/*.swift \
    "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR/Tests/visual/glass_preview.swift" \
    -swift-version 5 -D DEBUG -warnings-as-errors \
    -framework AppKit -framework CoreGraphics -framework IOKit \
    -o "$BUILD_DIR/WattsonGlassPreview"

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BUILD_DIR/WattsonGlassPreview" "$STAGED_APP/Contents/MacOS/WattsonGlassPreview"
cp "$ROOT_DIR/Tests/visual/glass_preview_Info.plist" "$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $RUN_PREVIEW_ID" "$STAGED_APP/Contents/Info.plist"
PREVIEW_VERSION="$(tr -d '\r\n' < "$ROOT_DIR/VERSION")"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PREVIEW_VERSION" "$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PREVIEW_VERSION" "$STAGED_APP/Contents/Info.plist"
cp "$ROOT_DIR/design/icon/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
/usr/bin/sips -s format png "$ROOT_DIR/design/icon/AppIcon.icns" \
    --out "$STAGED_APP/Contents/Resources/AppIconSettings.png" >/dev/null
for logo_resource in AppLogoColor.png AppLogoClearLight.png AppLogoClearDark.png; do
    cp "$ROOT_DIR/design/icon/in-app-logo/$logo_resource" \
        "$STAGED_APP/Contents/Resources/$logo_resource"
done
for dock_logo_resource in AppDockLogoColor.png AppDockLogoClearLight.png AppDockLogoClearDark.png; do
    cp "$ROOT_DIR/design/icon/dock-logo/$dock_logo_resource" \
        "$STAGED_APP/Contents/Resources/$dock_logo_resource"
done
/usr/bin/plutil -lint "$STAGED_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - \
    --entitlements "$ROOT_DIR/Tests/visual/glass_preview.entitlements" "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"
mkdir -p "$BUILD_DIR/preferences"
wattson_run_timeout 30 /usr/bin/env CFFIXED_USER_HOME="$BUILD_DIR/preferences" \
    "$STAGED_APP/Contents/MacOS/WattsonGlassPreview" --verify-defaults

if [[ "$KEEP_APP" == 1 ]]; then
    # Explicit handoff retains only one verified app, never backup bundles.
    wattson_unregister_app "$STAGED_APP"
    if [[ -d "$APP_BUNDLE" ]]; then
        wattson_unregister_app "$APP_BUNDLE"
        rm -rf -- "$APP_BUNDLE"
    fi
    mv "$STAGED_APP" "$APP_BUNDLE"
    echo "Verified app retained for visual review: $APP_BUNDLE"
else
    echo "Preview defaults self-test passed; temporary app bundles cleaned on exit."
fi
