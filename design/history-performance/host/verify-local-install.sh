#!/bin/bash
set -euo pipefail
repo='/Users/leoarrow/Project/mypackage/agents/电池功率'
evidence="$repo/.build/history-performance.noindex"
pkg="$repo/dist/Wattson-v4.3.11-macos-universal.pkg"
approved_sha="${1:?Pass the verified candidate package SHA-256}"
source_commit="${2:?Pass the frozen source commit}"
[[ "$approved_sha" =~ ^[0-9a-f]{64}$ && "$source_commit" =~ ^[0-9a-f]{40}$ ]]
app='/Applications/Wattson.app'
helper='/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper'
plist='/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist'
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
scratch="$(mktemp -d "$evidence/install-verify.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
cd "$repo/dist"
/usr/bin/shasum -a 256 -c SHA256SUMS.txt
expected_sha="$(/usr/bin/shasum -a 256 "$pkg" | /usr/bin/awk '{print $1}')"
[[ "$expected_sha" == "$approved_sha" ]]
wattson_run_timeout 90 /usr/sbin/pkgutil --expand-full "$pkg" "$scratch/expanded"
payload_app="$(/usr/bin/find "$scratch/expanded" -type d -path '*/Payload/Applications/Wattson.app' -print)"
payload_helper="$(/usr/bin/find "$scratch/expanded" -type f -path '*/Payload/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper' -print)"
payload_plist="$(/usr/bin/find "$scratch/expanded" -type f -path '*/Payload/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist' -print)"
[[ -d "$payload_app" && -f "$payload_helper" && -f "$payload_plist" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == 4.3.11 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == 4.3.11 ]]
[[ "$(/usr/sbin/pkgutil --pkg-info com.leoarrow.wattson.pkg | /usr/bin/awk -F': ' '$1 == "version" {print $2}')" == 4.3.11 ]]
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
/usr/bin/codesign --verify --strict --verbose=2 "$helper"
/usr/bin/diff -rq "$payload_app" "$app"
/usr/bin/cmp "$payload_helper" "$helper"
/usr/bin/cmp "$payload_plist" "$plist"
wattson_run_timeout 20 "$app/Contents/MacOS/Wattson" --helper-health-probe
wattson_run_timeout 20 "$app/Contents/MacOS/Wattson" --helper-v5-observation-probe > "$scratch/helper-v5.txt"
/usr/bin/grep -Fxq 'helperV5=v5' "$scratch/helper-v5.txt"
/usr/bin/open "$app"
for attempt in {1..50}; do
  if /usr/bin/pgrep -f '^/Applications/Wattson\.app/Contents/MacOS/Wattson($| )' > "$scratch/pids-before.txt"; then break; fi
  /bin/sleep 0.1
done
[[ "$(/usr/bin/awk 'END {print NR}' "$scratch/pids-before.txt")" == 1 ]]
/bin/sleep 10
/usr/bin/pgrep -f '^/Applications/Wattson\.app/Contents/MacOS/Wattson($| )' > "$scratch/pids-after.txt"
/usr/bin/cmp "$scratch/pids-before.txt" "$scratch/pids-after.txt"
/usr/bin/python3 - "$evidence/local-install-verified.json" "$pkg" "$expected_sha" "$scratch/pids-after.txt" "$source_commit" <<'PY'
import hashlib, json, sys
from pathlib import Path
from datetime import datetime, timezone
p = Path(sys.argv[2])
digest = hashlib.sha256(p.read_bytes()).hexdigest()
assert digest == sys.argv[3]
record = dict(checkedAtUTC=datetime.now(timezone.utc).isoformat(), version='4.3.11', sourceCommit=sys.argv[5],
    packageSHA256=digest, appAndHelperAndDaemonMatchVerifiedPayload=True,
    receiptVersion='4.3.11', signatureVerified=True, helperHealth=True,
    helperV5=True, canonicalAppPID=int(Path(sys.argv[4]).read_text()), stableSeconds=10,
    publicRelease=False)
Path(sys.argv[1]).write_text(json.dumps(record, indent=2)+'\n')
PY
echo LOCAL_INSTALL_VERIFIED
