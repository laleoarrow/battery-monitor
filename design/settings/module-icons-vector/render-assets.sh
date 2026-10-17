#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/../../.." && pwd)"
assets="$project/design/settings/module-icons-vector"
source "$project/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$project/.build/module-icons-vector.noindex"
scratch="$(mktemp -d "$project/.build/module-icons-vector.noindex/render.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
cd "$project"
deployment_target="$(uname -m)-apple-macosx12.0"
wattson_run_timeout 90 xcrun swiftc -swift-version 5 -warnings-as-errors \
    -module-cache-path "$scratch/module-cache" \
    Core/Settings.swift MenuBar/ModuleIconArtwork.swift "$assets/render-preview.swift" \
    -framework AppKit -o "$scratch/render-icons"
wattson_run_timeout 20 "$scratch/render-icons" "$assets" "$project/design/settings/sidebar-icons-vector"
wattson_run_timeout 120 xcrun swiftc -typecheck -D DEBUG -swift-version 5 -warnings-as-errors \
    -target "$deployment_target" -module-cache-path "$scratch/module-cache" \
    Core/*.swift MenuBar/*.swift Popover/*.swift
