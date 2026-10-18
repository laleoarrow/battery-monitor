#!/bin/bash
# Read-only verification of the user-authorized canonical 4.3.21 PKG upgrade.
set -euo pipefail
export LC_ALL=C
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
evidence="$repo/design/process-action-capsule/local-preview-v4.3.21"
pkg="$repo/dist/local-preview-v4.3.21/Wattson-v4.3.21-macos-universal.pkg"
approved_sha="${1:?Pass the approved package SHA-256}"
source_commit="${2:?Pass the full frozen source SHA}"
[[ "$approved_sha" =~ ^[0-9a-f]{64}$ && "$source_commit" =~ ^[0-9a-f]{40}$ ]]
[[ "$EUID" != 0 ]] || { echo 'Run verification as the current console user.' >&2; exit 65; }
app='/Applications/Wattson.app'
helper='/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper'
daemon='/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist'
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
[[ ! -e "$evidence/local-install-verified.json" ]] || exit 65
scratch="$(mktemp -d "$repo/.build/local-preview-v4.3.21.noindex/verify.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
(
    cd "$repo/dist/local-preview-v4.3.21"
    /usr/bin/shasum -a 256 -c SHA256SUMS.txt
)
[[ "$(/usr/bin/shasum -a 256 "$pkg" | /usr/bin/awk '{print $1}')" == "$approved_sha" ]]
/usr/bin/grep -Fxq "source_commit=$source_commit" "$repo/dist/local-preview-v4.3.21/Wattson-v4.3.21-release-info.txt"
wattson_run_timeout 90 /usr/sbin/pkgutil --expand-full "$pkg" "$scratch/expanded"
payload_app="$(/usr/bin/find "$scratch/expanded" -type d -path '*/Payload/Applications/Wattson.app' -print)"
payload_helper="$(/usr/bin/find "$scratch/expanded" -type f -path '*/Payload/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper' -print)"
payload_daemon="$(/usr/bin/find "$scratch/expanded" -type f -path '*/Payload/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist' -print)"
[[ -d "$payload_app" && -f "$payload_helper" && -f "$payload_daemon" ]]
wattson_cleanup_add_app "$payload_app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == 4.3.21 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == 4.3.21 ]]
[[ "$(/usr/sbin/pkgutil --pkg-info com.leoarrow.wattson.pkg | /usr/bin/awk -F': ' '$1 == "version" {print $2}')" == 4.3.21 ]]
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
/usr/bin/codesign --verify --strict --verbose=2 "$helper"
/usr/bin/diff -rq "$payload_app" "$app"
/usr/bin/cmp "$payload_helper" "$helper"
/usr/bin/cmp "$payload_daemon" "$daemon"
for binary in "$app/Contents/MacOS/Wattson" "$helper"; do
    /usr/bin/xcrun lipo "$binary" -verify_arch arm64 x86_64
    [[ "$(/usr/bin/xcrun lipo -archs "$binary" | /usr/bin/wc -w | /usr/bin/tr -d ' ')" == 2 ]]
done
# Both CLI probes exit before creating NSApplication or launching GUI.
wattson_run_timeout 20 "$app/Contents/MacOS/Wattson" --helper-health-probe
wattson_run_timeout 20 "$app/Contents/MacOS/Wattson" --helper-v5-observation-probe > "$scratch/helper-v5.txt"
/usr/bin/grep -Fxq 'helperV5=v5' "$scratch/helper-v5.txt"
wattson_run_timeout 20 /usr/bin/python3 "$evidence/verify_details.py" "$evidence" "$pkg" "$approved_sha" "$source_commit"
echo LOCAL_INSTALL_VERIFIED
