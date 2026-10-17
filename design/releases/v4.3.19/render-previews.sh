#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/../../.." && pwd)"
output="$project/design/releases/v4.3.19"
source "$project/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$project/.build/release-design.noindex"
scratch="$(mktemp -d "$project/.build/release-design.noindex/render.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
cd "$project"
mkdir -p "$output/previews"
wattson_run_timeout 90 xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$scratch/module-cache" \
    Core/Settings.swift MenuBar/ModuleIconArtwork.swift \
    design/settings/module-icons-vector/render-preview.swift \
    -framework AppKit -o "$scratch/render-settings-icons"
wattson_run_timeout 20 "$scratch/render-settings-icons" \
    "$output/previews" "$output/previews" "$output/previews"
wattson_run_timeout 120 xcrun swiftc -D DEBUG -swift-version 5 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx12.0" -module-cache-path "$scratch/module-cache" \
    Core/*.swift MenuBar/*.swift Popover/*.swift \
    design/popover/power-icons-vector/render-preview.swift \
    -framework AppKit -framework CoreGraphics -framework IOKit -o "$scratch/render-power-icons"
wattson_run_timeout 30 "$scratch/render-power-icons" "$output/previews"
wattson_run_timeout 120 xcrun swiftc -D DEBUG -swift-version 5 -warnings-as-errors \
    -target "$(uname -m)-apple-macosx12.0" -module-cache-path "$scratch/module-cache" \
    Core/*.swift MenuBar/*.swift Popover/*.swift "$output/render-process-preview.swift" \
    -framework AppKit -framework CoreGraphics -framework IOKit -o "$scratch/render-process"
wattson_run_timeout 20 "$scratch/render-process" "$output/previews"
