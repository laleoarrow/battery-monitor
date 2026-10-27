#!/bin/bash
# Inner owner; all extracted payloads and subprocesses are cleaned before return.
set -euo pipefail
unset PYTHONOPTIMIZE
export PYTHONDONTWRITEBYTECODE=1 LC_ALL=C
evidence="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$evidence/../../.." && pwd)"
[[ "$#" == 4 && "$EUID" != 0 ]] || exit 64
pkg="$1"; source_commit="$2"; before="$3"; results="$4"
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
wattson_run_timeout 30 /usr/bin/python3 "$evidence/installation_state.py" preflight "$pkg" "$source_commit" "$before"
mkdir -p "$repo/.build/battery-time-install.noindex"
scratch="$(mktemp -d "$repo/.build/battery-time-install.noindex/verify.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
cd "$(dirname "$pkg")"
wattson_run_timeout 60 /usr/bin/shasum -a 256 -c SHA256SUMS.txt > "$results/checksums.log" 2>&1
wattson_run_timeout 90 /usr/sbin/pkgutil --expand-full "$pkg" "$scratch/expanded" > "$results/expand.log" 2>&1
payload_app="$(/usr/bin/find "$scratch/expanded" -type d -path '*/Payload/Applications/Wattson.app' -print)"
payload_helper="$(/usr/bin/find "$scratch/expanded" -type f -path '*/Payload/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper' -print)"
payload_daemon="$(/usr/bin/find "$scratch/expanded" -type f -path '*/Payload/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist' -print)"
[[ -d "$payload_app" && -f "$payload_helper" && -f "$payload_daemon" ]] || exit 65
wattson_cleanup_add_app "$payload_app"
app='/Applications/Wattson.app'
helper='/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper'
daemon='/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist'
wattson_run_timeout 30 /usr/bin/codesign --verify --deep --strict --verbose=2 "$app" > "$results/app-signature.log" 2>&1
wattson_run_timeout 30 /usr/bin/codesign --verify --strict --verbose=2 "$helper" > "$results/helper-signature.log" 2>&1
wattson_run_timeout 30 /usr/bin/diff -rq "$payload_app" "$app" > "$results/app-payload-diff.log" 2>&1
wattson_run_timeout 15 /usr/bin/cmp "$payload_helper" "$helper"
wattson_run_timeout 15 /usr/bin/cmp "$payload_daemon" "$daemon"
for binary in "$app/Contents/MacOS/Wattson" "$helper"; do
    for architecture in arm64 x86_64; do
        wattson_run_timeout 15 /usr/bin/xcrun lipo "$binary" -verify_arch "$architecture"
    done
    [[ "$(/usr/bin/xcrun lipo -archs "$binary" | /usr/bin/wc -w | /usr/bin/tr -d ' ')" == 2 ]] || exit 65
done
# Fixed read-only commands exit before constructing NSApplication.
wattson_run_timeout 20 "$app/Contents/MacOS/Wattson" --helper-health-probe > "$results/helper-health.log" 2>&1
wattson_run_timeout 20 "$app/Contents/MacOS/Wattson" --helper-v5-observation-probe > "$results/helper-v5.log" 2>&1
/usr/bin/grep -Fxq 'helperV5=v5' "$results/helper-v5.log"
wattson_run_timeout 30 /usr/bin/python3 "$evidence/installation_state.py" details \
    "$pkg" "$source_commit" "$before" "$results/pending-cleanup.json" "$scratch" "$payload_app"
