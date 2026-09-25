#!/bin/bash
# Build and stage the isolated visible QA app, then run its defaults-only CLI
# check. This never opens UI, kills an app, changes the canonical installation,
# or requests capture permissions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW_ROOT="$ROOT_DIR/.build/preview.noindex"
APP_BUNDLE="$PREVIEW_ROOT/Wattson Glass Preview.app"
PREVIEW_ID="com.leoarrow.wattson.glass-preview"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ $# -ne 0 ]]; then
    echo "usage: $0 (build only; launch the resulting .app separately)" >&2
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
    [[ "$EXISTING_ID" == "$PREVIEW_ID" ]] || {
        echo "Refusing to replace an unrelated app bundle." >&2
        exit 2
    }
fi

mkdir -p "$PREVIEW_ROOT"
BUILD_DIR="$(mktemp -d "$PREVIEW_ROOT/build.XXXXXX")"
STAGED_APP="$BUILD_DIR/Wattson Glass Preview.app"
cleanup() {
    if [[ -d "$STAGED_APP" ]]; then
        "$LSREGISTER" -u "$STAGED_APP" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$BUILD_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

xcrun swiftc \
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
"$STAGED_APP/Contents/MacOS/WattsonGlassPreview" --verify-defaults

# Publish only a verified build, without retaining indexable backup bundles.
"$LSREGISTER" -u "$STAGED_APP" >/dev/null 2>&1 || true
if [[ -d "$APP_BUNDLE" ]]; then
    "$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true
    rm -rf -- "$APP_BUNDLE"
fi
mv "$STAGED_APP" "$APP_BUNDLE"
echo "Built and defaults self-test passed without opening UI: $APP_BUNDLE"
