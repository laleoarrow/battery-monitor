#!/bin/bash
set -euo pipefail
[[ $# == 1 && "$HOME" == /Users/admin && "$(/usr/sbin/sysctl -n hw.model)" == VirtualMac* ]] || exit 65
share='/Volumes/My Shared Files/normaldrag'
source "$share/fixture/lifecycle/local_cleanup.sh"
wattson_cleanup_init
base="$HOME/Project/.build/wattson-ipc-diag.noindex"
if [[ ! -e "$base" ]]; then mkdir -p "$base"; wattson_cleanup_add_dir "$base"; fi
[[ -d "$base" && ! -L "$base" ]] || exit 65
run_dir="$(mktemp -d "$base/run.XXXXXX")"
wattson_cleanup_add_dir "$run_dir"
wattson_run_timeout 12 /usr/bin/xcrun swiftc -swift-version 5 -warnings-as-errors "$share/ipc-diag/reader.swift" -o "$run_dir/reader"
wattson_run_timeout 12 "$run_dir/reader" "$share/ipc-diag/$1" "$run_dir"
