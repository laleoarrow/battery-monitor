#!/bin/bash
# Isolated browser render; no user profile or remote request is used.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [[ $# -lt 1 || $# -gt 2 || ! -f "$1/package.json" || ( $# == 2 && "$2" != --svg-only ) ]]; then
    echo 'usage: render-gallery.sh EXISTING_PLAYWRIGHT_PACKAGE_DIRECTORY [--svg-only]' >&2
    exit 64
fi
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/release-gallery.noindex"
RUN_DIR="$(mktemp -d "$ROOT_DIR/.build/release-gallery.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$RUN_DIR"
mkdir -p "$RUN_DIR/tmp"
wattson_run_timeout 120 /usr/bin/env TMPDIR="$RUN_DIR/tmp" node \
    "$SCRIPT_DIR/render-gallery.mjs" "$1" "$RUN_DIR" "${2:-}"
