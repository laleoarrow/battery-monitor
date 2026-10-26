#!/bin/bash
# Package the auditable, source-only issue #19 support collector.
set -euo pipefail
umask 077
export COPYFILE_DISABLE=1
ROOT_DIR="$(cd "$(/usr/bin/dirname "$0")/.." && /bin/pwd)"
# shellcheck source=lib/local_cleanup.sh
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
/bin/mkdir -p "$ROOT_DIR/.build/issue19-support.noindex"
SUPPORT_SCRATCH="$(/usr/bin/mktemp -d "$ROOT_DIR/.build/issue19-support.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$SUPPORT_SCRATCH"
STAGING="$SUPPORT_SCRATCH/Wattson-Issue19-Support"
wattson_run_timeout 15 /bin/mkdir "$STAGING"
for item in Collect-Wattson-Issue19.command collect.js lifecycle.sh README.md REPORT-README.txt; do
    wattson_run_timeout 15 /bin/cp "$ROOT_DIR/Support/Issue19/$item" "$STAGING/$item"
done
wattson_run_timeout 15 /bin/chmod 755 "$STAGING/Collect-Wattson-Issue19.command"
wattson_run_timeout 15 /bin/bash -n "$STAGING/Collect-Wattson-Issue19.command" "$STAGING/lifecycle.sh"
DIST_DIR="$ROOT_DIR/dist/support"
wattson_run_timeout 15 /bin/mkdir -p "$DIST_DIR"
ARCHIVE_NAME=Wattson-Issue19-Support-v2.zip
wattson_run_timeout 45 /usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$STAGING" "$SUPPORT_SCRATCH/$ARCHIVE_NAME"
wattson_run_timeout 45 /usr/bin/unzip -t "$SUPPORT_SCRATCH/$ARCHIVE_NAME" >/dev/null
cd "$SUPPORT_SCRATCH"
wattson_run_timeout 15 /usr/bin/shasum -a 256 "$ARCHIVE_NAME" > Wattson-Issue19-Support-v2.sha256
for artifact in "$ARCHIVE_NAME" Wattson-Issue19-Support-v2.sha256; do
    wattson_run_timeout 15 /bin/mv "$SUPPORT_SCRATCH/$artifact" "$DIST_DIR/$artifact"
done
echo "Built: $DIST_DIR/$ARCHIVE_NAME"
