#!/bin/bash
# Verify that a DMG contains one byte-identical Wattson installer PKG.
set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    echo "usage: $0 /path/to/Wattson.dmg [/path/to/Wattson.pkg]" >&2
    exit 2
fi

DMG_PATH="$1"
EXPECTED_PKG="${2:-}"
[[ -f "$DMG_PATH" && ! -L "$DMG_PATH" ]] || {
    echo "DMG must be a regular file: $DMG_PATH" >&2
    exit 1
}
if [[ -n "$EXPECTED_PKG" ]]; then
    [[ -f "$EXPECTED_PKG" && ! -L "$EXPECTED_PKG" ]] || {
        echo "expected PKG must be a regular file: $EXPECTED_PKG" >&2
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
if [[ "${#VISIBLE_ITEMS[@]}" -ne 1 || "${VISIBLE_ITEMS[0]}" != *.pkg ]]; then
    echo "DMG must expose exactly one installer PKG" >&2
    printf 'found: %s\n' "${VISIBLE_ITEMS[@]}" >&2
    exit 1
fi
EMBEDDED_PKG="${VISIBLE_ITEMS[0]}"
[[ -f "$EMBEDDED_PKG" && ! -L "$EMBEDDED_PKG" ]]

if [[ -n "$EXPECTED_PKG" ]]; then
    [[ "$(/usr/bin/basename "$EMBEDDED_PKG")" == "$(/usr/bin/basename "$EXPECTED_PKG")" ]] \
        || { echo "embedded PKG name does not match release PKG" >&2; exit 1; }
    /usr/bin/cmp -s "$EXPECTED_PKG" "$EMBEDDED_PKG" \
        || { echo "embedded PKG bytes differ from release PKG" >&2; exit 1; }
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

PAYLOAD_FILES="$(
    /usr/sbin/pkgutil --payload-files "$EMBEDDED_PKG" \
        | /usr/bin/sed 's#^\./##'
)"
/usr/bin/grep -Fxq "Applications/Wattson.app/Contents/MacOS/Wattson" <<< "$PAYLOAD_FILES"
/usr/bin/grep -Fxq \
    "Library/PrivilegedHelperTools/com.leoarrow.wattson.helper" \
    <<< "$PAYLOAD_FILES"
/usr/bin/grep -Fxq \
    "Library/LaunchDaemons/com.leoarrow.wattson.helper.plist" \
    <<< "$PAYLOAD_FILES"

if [[ "${WATTSON_EXPECT_DMG_SIGNED:-0}" == "1" ]]; then
    /usr/bin/codesign --verify --strict "$DMG_PATH"
fi

echo "Mounted DMG verified: one byte-identical canonical installer PKG"
