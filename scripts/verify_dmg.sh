#!/bin/bash
# Verify the mounted image, including the cross-user permission regression.
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 /path/to/Wattson.dmg" >&2
    exit 2
fi

DMG_PATH="$1"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wattson-dmg-verify.XXXXXX")"
ATTACHED=0

cleanup() {
    if [ "$ATTACHED" = "1" ]; then
        hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi
    rm -rf "$MOUNT_DIR"
}
trap cleanup EXIT

hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null
ATTACHED=1

ROOT_MODE="$(stat -f '%OLp' "$MOUNT_DIR")"
if [ "$ROOT_MODE" != "755" ]; then
    echo "DMG root must be 0755, got $ROOT_MODE" >&2
    exit 1
fi

shopt -s nullglob
VISIBLE_ITEMS=("$MOUNT_DIR"/*)
if [ "${#VISIBLE_ITEMS[@]}" -ne 1 ] || [ "${VISIBLE_ITEMS[0]##*/}" != "Install Wattson.app" ]; then
    echo "DMG must expose only Install Wattson.app" >&2
    printf 'found: %s\n' "${VISIBLE_ITEMS[@]}" >&2
    exit 1
fi

INSTALLER="$MOUNT_DIR/Install Wattson.app"
INSTALLER_EXECUTABLE="$INSTALLER/Contents/MacOS/Install Wattson"
test -f "$MOUNT_DIR/.metadata_never_index"
test ! -e "$MOUNT_DIR/Quick Start.txt"
test ! -e "$MOUNT_DIR/Install Wattson.command"
test ! -e "$MOUNT_DIR/Wattson.app"
test -x "$INSTALLER_EXECUTABLE"

# The old image only worked for its creator because mktemp's 0700 mode leaked
# into the volume. Check every shipped directory and file from another user's
# permission bits, not merely from the current owner's point of view.
while IFS= read -r -d '' SHIPPED_PATH; do
    PATH_MODE="$(stat -f '%OLp' "$SHIPPED_PATH")"
    PATH_MODE_VALUE=$((8#$PATH_MODE))
    if [ -d "$SHIPPED_PATH" ]; then
        if (( (PATH_MODE_VALUE & 5) != 5 )); then
            echo "directory is not world-readable/traversable: $PATH_MODE $SHIPPED_PATH" >&2
            exit 1
        fi
    elif [ -f "$SHIPPED_PATH" ]; then
        if (( (PATH_MODE_VALUE & 4) != 4 )); then
            echo "file is not world-readable: $PATH_MODE $SHIPPED_PATH" >&2
            exit 1
        fi
        if (( (PATH_MODE_VALUE & 64) != 0 && (PATH_MODE_VALUE & 1) == 0 )); then
            echo "executable is not world-executable: $PATH_MODE $SHIPPED_PATH" >&2
            exit 1
        fi
    fi
done < <(/usr/bin/find "$MOUNT_DIR" -print0)

codesign --verify --deep --strict "$INSTALLER"
"$INSTALLER_EXECUTABLE" --verify

echo "✅ Mounted DMG verified: one installer, readable root, valid payload"
