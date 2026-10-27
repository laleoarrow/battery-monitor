#!/bin/bash
# Local, isolated browser proof. Does not contact mail or publish artwork.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [[ $# != 1 || ! -f "$1/package.json" ]]; then
    echo "usage: $0 EXISTING_PLAYWRIGHT_PACKAGE_DIRECTORY" >&2
    exit 64
fi
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
RUN_DIR="$SCRIPT_DIR/.preview-$(/usr/bin/uuidgen).noindex"
wattson_cleanup_add_dir "$RUN_DIR"
mkdir -p "$RUN_DIR/tmp"
_WATTSON_RUNNER_STARTING=1
/usr/bin/python3 "$ROOT_DIR/scripts/lib/run_owned.py" --grace 60 --timeout 120 -- \
    /usr/bin/env TMPDIR="$RUN_DIR/tmp" node "$SCRIPT_DIR/render-preview.mjs" "$1" "$RUN_DIR" &
_WATTSON_RUNNER_PID=$!
_wattson_runner_registered
STATUS=0
wait "$_WATTSON_RUNNER_PID" || STATUS=$?
_WATTSON_RUNNER_PID=''
exit "$STATUS"
