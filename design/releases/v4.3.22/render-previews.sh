#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/../../.." && pwd)"
output="$project/design/releases/v4.3.22"
source "$project/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$project/.build/release-design-v4322.noindex"
scratch="$(mktemp -d "$project/.build/release-design-v4322.noindex/render.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
cd "$project"
mkdir -p "$output/previews"
wattson_run_timeout 120 xcrun swiftc -D DEBUG -swift-version 5 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx12.0" -module-cache-path "$scratch/module-cache" \
    Core/*.swift MenuBar/*.swift Popover/*.swift "$output/render-process-preview.swift" \
    -framework AppKit -framework CoreGraphics -framework IOKit -o "$scratch/render-process"
wattson_run_timeout 20 "$scratch/render-process" "$output/previews"
