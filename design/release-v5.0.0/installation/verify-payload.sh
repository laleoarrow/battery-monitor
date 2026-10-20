#!/bin/bash
# Inner owner: shared EXIT cleanup runs here, where every child was spawned.
set -euo pipefail
unset PYTHONOPTIMIZE
export PYTHONDONTWRITEBYTECODE=1 LC_ALL=C
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
evidence="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ "$#" == 6 ]] || exit 64
pkg="$1"; approved_sha="$2"; source_commit="$3"; provenance="$4"; before="$5"; attempt="$6"
[[ "$pkg" == /* && -f "$pkg" && "$approved_sha" =~ ^[0-9a-f]{64}$ && "$source_commit" =~ ^[0-9a-f]{40}$ ]] || exit 64
[[ "$EUID" != 0 && "$attempt" == "$evidence/"checks-* && -d "$attempt" ]] || exit 65
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
wattson_run_timeout 30 /usr/bin/python3 "$evidence/verify_details.py" identity "$pkg" "$approved_sha" "$source_commit" "$provenance" "$before"
mkdir -p "$repo/.build/release-v5.0.0-install.noindex"
scratch="$(mktemp -d "$repo/.build/release-v5.0.0-install.noindex/verify.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
cd "$(dirname "$pkg")"
wattson_run_timeout 60 /usr/bin/shasum -a 256 -c SHA256SUMS.txt > "$attempt/public-checksums.log" 2> "$attempt/public-checksums.err"
wattson_run_timeout 90 /usr/sbin/pkgutil --expand-full "$pkg" "$scratch/expanded" > "$attempt/expand.log" 2> "$attempt/expand.err"
payload_app="$(/usr/bin/find "$scratch/expanded" -type d -path '*/Payload/Applications/Wattson.app' -print)"
payload_helper="$(/usr/bin/find "$scratch/expanded" -type f -path '*/Payload/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper' -print)"
payload_daemon="$(/usr/bin/find "$scratch/expanded" -type f -path '*/Payload/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist' -print)"
[[ -d "$payload_app" && -f "$payload_helper" && -f "$payload_daemon" ]] || exit 65
wattson_cleanup_add_app "$payload_app"
app='/Applications/Wattson.app'
helper='/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper'
daemon='/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist'
for field in CFBundleShortVersionString CFBundleVersion; do
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$field" "$app/Contents/Info.plist")" == 5.0.0 ]] || exit 65
done
wattson_run_timeout 30 /usr/bin/codesign --verify --deep --strict --verbose=2 "$app" > "$attempt/app-signature.log" 2>&1
wattson_run_timeout 30 /usr/bin/codesign --verify --strict --verbose=2 "$helper" > "$attempt/helper-signature.log" 2>&1
wattson_run_timeout 30 /usr/bin/diff -rq "$payload_app" "$app" > "$attempt/app-payload-diff.log" 2>&1
/usr/bin/cmp "$payload_helper" "$helper"
/usr/bin/cmp "$payload_daemon" "$daemon"
for binary in "$app/Contents/MacOS/Wattson" "$helper"; do
    for architecture in arm64 x86_64; do
        wattson_run_timeout 15 /usr/bin/xcrun lipo "$binary" -verify_arch "$architecture"
    done
    [[ "$(/usr/bin/xcrun lipo -archs "$binary" | /usr/bin/wc -w | /usr/bin/tr -d ' ')" == 2 ]] || exit 65
done
# These fixed CLI probes exit before NSApplication is created; neither opens GUI.
wattson_run_timeout 20 "$app/Contents/MacOS/Wattson" --helper-health-probe > "$attempt/helper-health.log" 2>&1
wattson_run_timeout 20 "$app/Contents/MacOS/Wattson" --helper-v5-observation-probe > "$attempt/helper-v5.log" 2>&1
/usr/bin/grep -Fxq 'helperV5=v5' "$attempt/helper-v5.log"
wattson_run_timeout 25 /usr/bin/python3 "$evidence/verify_details.py" details "$before" "$pkg" "$approved_sha" "$source_commit" "$attempt/checks-passed-before-cleanup.json" "$scratch" "$payload_app" > "$attempt/details.log" 2> "$attempt/details.err"
