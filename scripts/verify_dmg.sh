#!/bin/bash
# Verify a helper-free DMG against the app from the same release build or PKG.
set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    echo "usage: $0 /path/to/Wattson.dmg [/path/to/expected/Wattson.app]" >&2
    exit 2
fi

DMG_PATH="$1"
EXPECTED_APP="${2:-}"
[[ -f "$DMG_PATH" && ! -L "$DMG_PATH" ]] || {
    echo "DMG must be a regular file: $DMG_PATH" >&2
    exit 1
}
if [[ -n "$EXPECTED_APP" ]]; then
    [[ -d "$EXPECTED_APP" && ! -L "$EXPECTED_APP" ]] || {
        echo "expected app must be a directory: $EXPECTED_APP" >&2
        exit 1
    }
fi

MOUNT_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/wattson-dmg-verify.XXXXXX")"
ATTACHED=0

cleanup() {
    if [[ "$ATTACHED" == "1" ]]; then
        /usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi
    /bin/rm -rf -- "$MOUNT_DIR"
}
trap cleanup EXIT

/usr/bin/hdiutil attach \
    -nobrowse \
    -readonly \
    -mountpoint "$MOUNT_DIR" \
    "$DMG_PATH" >/dev/null
ATTACHED=1

ROOT_MODE="$(/usr/bin/stat -f '%OLp' "$MOUNT_DIR")"
[[ "$ROOT_MODE" == "755" ]] || {
    echo "DMG root must be 0755, got $ROOT_MODE" >&2
    exit 1
}
[[ -f "$MOUNT_DIR/.metadata_never_index" ]]

shopt -s nullglob
VISIBLE_ITEMS=("$MOUNT_DIR"/*)
if [[ "${#VISIBLE_ITEMS[@]}" -ne 2 \
    || ! -d "$MOUNT_DIR/Wattson.app" || -L "$MOUNT_DIR/Wattson.app" \
    || ! -L "$MOUNT_DIR/Applications" \
    || "$(/usr/bin/readlink "$MOUNT_DIR/Applications")" != /Applications ]]; then
    echo "DMG must expose only Wattson.app and an Applications link" >&2
    printf 'found: %s\n' "${VISIBLE_ITEMS[@]}" >&2
    exit 1
fi
EMBEDDED_APP="$MOUNT_DIR/Wattson.app"
APP_INFO="$EMBEDDED_APP/Contents/Info.plist"
APP_BIN="$EMBEDDED_APP/Contents/MacOS/Wattson"
[[ -f "$APP_BIN" && ! -L "$APP_BIN" ]]
if /usr/bin/find "$EMBEDDED_APP" \
    \( -name 'com.leoarrow.wattson.helper*' -o -name '*.pkg' -o -name preinstall -o -name postinstall \) \
    -print -quit | /usr/bin/grep -q .; then
    echo "read-only DMG app must not bundle a privileged installer or helper" >&2
    exit 1
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_INFO")" == com.leoarrow.wattson ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_INFO")" == 12.0 ]]
/usr/bin/xcrun lipo "$APP_BIN" -verify_arch arm64 x86_64
/usr/bin/codesign --verify --deep --strict "$EMBEDDED_APP"

if [[ -n "$EXPECTED_APP" ]]; then
    /usr/bin/diff -qr "$EXPECTED_APP" "$EMBEDDED_APP" \
        || { echo "DMG app bytes differ from the expected release app" >&2; exit 1; }
fi

while IFS= read -r -d '' shipped_path; do
    path_mode="$(/usr/bin/stat -f '%OLp' "$shipped_path")"
    path_mode_value=$((8#$path_mode))
    if [[ -d "$shipped_path" ]]; then
        (( (path_mode_value & 5) == 5 )) || {
            echo "directory is not world-readable/traversable: $path_mode $shipped_path" >&2
            exit 1
        }
    elif [[ -f "$shipped_path" ]]; then
        (( (path_mode_value & 4) == 4 )) || {
            echo "file is not world-readable: $path_mode $shipped_path" >&2
            exit 1
        }
    fi
done < <(/usr/bin/find "$MOUNT_DIR" -print0)

if [[ "${WATTSON_EXPECT_DMG_SIGNED:-0}" == "1" ]]; then
    /usr/bin/codesign --verify --strict "$DMG_PATH"
fi

echo "Mounted DMG verified: helper-free app and Applications link"
