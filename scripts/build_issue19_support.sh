#!/bin/bash
# Package the auditable, source-only issue #19 support collector.
set -euo pipefail
umask 077
export COPYFILE_DISABLE=1
ROOT_DIR="$(cd "$(/usr/bin/dirname "$0")/.." && /bin/pwd)"
# shellcheck source=../Support/Issue19/lifecycle.sh
source "$ROOT_DIR/Support/Issue19/lifecycle.sh"
support_begin "$ROOT_DIR/.build/issue19-support.noindex"
STAGING="$SUPPORT_SCRATCH/Wattson-Issue19-Support"
/bin/mkdir "$STAGING"
for item in Collect-Wattson-Issue19.command collect.js lifecycle.sh README.md REPORT-README.txt; do
    /bin/cp "$ROOT_DIR/Support/Issue19/$item" "$STAGING/$item"
done
/bin/chmod 755 "$STAGING/Collect-Wattson-Issue19.command"
/bin/bash -n "$STAGING/Collect-Wattson-Issue19.command" "$STAGING/lifecycle.sh"
DIST_DIR="$ROOT_DIR/dist/support"
/bin/mkdir -p "$DIST_DIR"
ARCHIVE_NAME=Wattson-Issue19-Support-v2.zip
/usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$STAGING" "$SUPPORT_SCRATCH/$ARCHIVE_NAME"
/usr/bin/unzip -t "$SUPPORT_SCRATCH/$ARCHIVE_NAME" >/dev/null
/bin/mv "$SUPPORT_SCRATCH/$ARCHIVE_NAME" "$DIST_DIR/$ARCHIVE_NAME"
(
    cd "$DIST_DIR"
    /usr/bin/shasum -a 256 "$ARCHIVE_NAME" > Wattson-Issue19-Support-v2.sha256
)
echo "Built: $DIST_DIR/$ARCHIVE_NAME"
