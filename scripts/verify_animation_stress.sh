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

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wattson-animation-stress.XXXXXX")"
trap 'rm -rf -- "$BUILD_DIR"' EXIT
BINARY="$BUILD_DIR/AnimationStress"

/usr/sbin/taskpolicy -b /usr/bin/nice -n 15 /usr/bin/xcrun swiftc \
    "$ROOT_DIR"/Core/*.swift \
    "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR/tests/animation_stress/main.swift" \
    -D DEBUG \
    -framework AppKit \
    -framework CoreGraphics \
    -framework IOKit \
    -o "$BINARY"

/usr/sbin/taskpolicy -b /usr/bin/nice -n 15 "$BINARY" "$ITERATIONS"
