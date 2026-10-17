#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/../../.." && pwd)"
assets="$project/design/popover/power-icons-vector"
source "$project/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$project/.build/power-icons.noindex"
scratch="$(mktemp -d "$project/.build/power-icons.noindex/render.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
cd "$project"
wattson_run_timeout 120 xcrun swiftc -D DEBUG -swift-version 5 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx12.0" -module-cache-path "$scratch/module-cache" \
    Core/*.swift MenuBar/*.swift Popover/*.swift "$assets/render-preview.swift" \
    -framework AppKit -framework CoreGraphics -framework IOKit -o "$scratch/render-icons"
wattson_run_timeout 30 "$scratch/render-icons" "$assets"
