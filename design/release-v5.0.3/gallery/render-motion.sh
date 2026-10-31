#!/bin/bash
# Own the isolated browser and all disposable frame/encoding files.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[[ $# == 1 && -f "$1/package.json" ]] || { echo 'usage: render-motion.sh EXISTING_PLAYWRIGHT_PACKAGE_DIRECTORY' >&2; exit 64; }
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/release-motion.noindex"
RUN_DIR="$(mktemp -d "$ROOT_DIR/.build/release-motion.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$RUN_DIR"
mkdir "$RUN_DIR/tmp"
wattson_run_timeout 600 /usr/bin/env TMPDIR="$RUN_DIR/tmp" node "$SCRIPT_DIR/render-motion.mjs" "$1" "$RUN_DIR"
