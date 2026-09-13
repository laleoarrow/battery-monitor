#!/bin/bash
# Build and stage the isolated visible QA app, then run its defaults-only CLI
# check. This never opens UI, kills an app, changes the canonical installation,
# or requests capture permissions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW_ROOT="$ROOT_DIR/dist/liquid-glass-option-20260913/preview-app"
APP_BUNDLE="$PREVIEW_ROOT/Wattson Glass Preview.app"
PREVIEW_ID="com.leoarrow.wattson.glass-preview"

if [[ $# -ne 0 ]]; then
    echo "usage: $0 (build only; launch the resulting .app separately)" >&2
    exit 2
fi
if /usr/bin/pgrep -x WattsonGlassPreview >/dev/null; then
    echo "Close Wattson Glass Preview before rebuilding its bundle." >&2
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
xcrun swiftc \
    "$ROOT_DIR"/Core/*.swift \
    "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR/Tests/visual/glass_preview.swift" \
    -swift-version 5 -D DEBUG -warnings-as-errors \
    -framework AppKit -framework CoreGraphics -framework IOKit \
    -o "$BUILD_DIR/WattsonGlassPreview"

if [[ -d "$APP_BUNDLE" ]]; then
    mv "$APP_BUNDLE" "$BUILD_DIR/previous-Wattson Glass Preview.app"
fi
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/WattsonGlassPreview" "$APP_BUNDLE/Contents/MacOS/WattsonGlassPreview"
cp "$ROOT_DIR/Tests/visual/glass_preview_Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/design/icon/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
/usr/bin/sips -s format png "$ROOT_DIR/design/icon/AppIcon.icns" \
    --out "$APP_BUNDLE/Contents/Resources/AppIconSettings.png" >/dev/null
for logo_resource in AppLogoColor.png AppLogoClearLight.png AppLogoClearDark.png; do
    cp "$ROOT_DIR/design/icon/in-app-logo/$logo_resource" \
        "$APP_BUNDLE/Contents/Resources/$logo_resource"
done
/usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --sign - \
    --entitlements "$ROOT_DIR/Tests/visual/glass_preview.entitlements" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
"$APP_BUNDLE/Contents/MacOS/WattsonGlassPreview" --verify-defaults
echo "Built and defaults self-test passed without opening UI: $APP_BUNDLE"
