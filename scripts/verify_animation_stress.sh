#!/bin/bash
# Compiles and runs the no-window popover entrance-animation stress harness.
# It uses a fresh temporary directory and never installs, launches, or stops
# the user-facing app.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ITERATIONS="${1:-20000}"

if (( $# > 1 )) || [[ ! "$ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
    echo "usage: $0 [positive-iteration-count]" >&2
    exit 64
fi

source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/animation-stress.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/animation-stress.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
BINARY="$BUILD_DIR/AnimationStress"
mkdir -p "$BUILD_DIR/isolated-home"

wattson_run /usr/sbin/taskpolicy -b /usr/bin/nice -n 15 /usr/bin/xcrun swiftc \
    "$ROOT_DIR"/Core/*.swift \
    "$ROOT_DIR/MenuBar/ModuleIconArtwork.swift" \
    "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR/tests/animation_stress/main.swift" \
    -D DEBUG \
    -framework AppKit \
    -framework CoreGraphics \
    -framework IOKit \
    -o "$BINARY"

wattson_run_timeout 120 /usr/bin/env CFFIXED_USER_HOME="$BUILD_DIR/isolated-home" \
    /usr/sbin/taskpolicy -b /usr/bin/nice -n 15 "$BINARY" "$ITERATIONS"
