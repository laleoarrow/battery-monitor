#!/bin/bash
# --run-gui requires a disposable logged-in macOS GUI VM.
set -euo pipefail
umask 077
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---compile-only}"
ITERATIONS="${2:-2000}"
if [[ "$MODE" != --compile-only && "$MODE" != --run-gui ]] || (( $# > 2 )) \
    || [[ "$MODE" == --compile-only && $# -gt 1 ]]; then
    echo "usage: $0 [--compile-only | --run-gui [ITERATIONS]]" >&2
    exit 64
fi
if [[ ! "$ITERATIONS" =~ ^[1-9][0-9]{2,4}$ ]] || (( ITERATIONS < 100 || ITERATIONS > 20000 )); then
    echo "ITERATIONS must be between 100 and 20000" >&2
    exit 64
fi
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/renderers.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/renderers.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
export WATTSON_TEST_DEFAULTS_SUITE="Wattson.Performance.$(/usr/bin/uuidgen)"
wattson_cleanup_add_defaults "$WATTSON_TEST_DEFAULTS_SUITE"
BENCHMARK="$BUILD_DIR/renderer-benchmark"
wattson_run_timeout 300 xcrun swiftc "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR/tests/performance/main.swift" -O -D DEBUG -D WATTSON_PERF_COUNTERS \
    -framework AppKit -framework CoreGraphics -framework IOKit -o "$BENCHMARK"
if [[ "$MODE" == --compile-only ]]; then
    echo "RENDERERS_COMPILE_OK"
    exit 0
fi
wattson_run_timeout 120 /usr/bin/env -u CFFIXED_USER_HOME /usr/bin/time -l "$BENCHMARK" "$ITERATIONS"
