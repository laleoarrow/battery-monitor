#!/bin/bash
# Read-only verification of the authorized local 4.3.24 candidate installation.
set -euo pipefail
unset PYTHONOPTIMIZE
export PYTHONDONTWRITEBYTECODE=1 LC_ALL=C
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
evidence="$repo/design/system-metric-authority"
pkg="$repo/dist/Wattson-v4.3.24-macos-universal.pkg"
approved_sha='a988b725eae28a14e258699bb8c95cb8a90d90ad7802d8ede8a6fa144ff2c591'
[[ "$EUID" != 0 ]] || exit 65
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$repo/.build/system-install-verify.noindex"
scratch="$(mktemp -d "$repo/.build/system-install-verify.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
if [[ "$#" == 0 ]]; then
    [[ ! -e "$evidence/install-verification.json" ]] || exit 65
    wattson_run_script "$0" --payload "$scratch/checks.json"
    report="$(cat "$scratch/checks.json")"
    rm "$scratch/checks.json"
    rmdir "$scratch"
    /usr/bin/python3 -c 'import json,sys; report=json.load(sys.stdin); report["payloadCleanupPassed"]=True; out=open(sys.argv[1],"x"); out.write(json.dumps(report,indent=2)+"\n"); out.close()' \
        "$evidence/install-verification.json" <<< "$report"
    echo LOCAL_CANDIDATE_INSTALL_VERIFIED
    exit 0
fi
[[ "$#" == 2 && "$1" == --payload && "$2" == "$repo/.build/system-install-verify.noindex/"* ]] || exit 64
report_path="$2"
[[ "$(/usr/bin/shasum -a 256 "$pkg" | /usr/bin/awk '{print $1}')" == "$approved_sha" ]]
wattson_run_timeout 90 /usr/sbin/pkgutil --expand-full "$pkg" "$scratch/expanded"
payload_app="$(/usr/bin/find "$scratch/expanded" -type d -path '*/Payload/Applications/Wattson.app' -print)"
payload_helper="$(/usr/bin/find "$scratch/expanded" -type f -path '*/Payload/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper' -print)"
payload_daemon="$(/usr/bin/find "$scratch/expanded" -type f -path '*/Payload/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist' -print)"
[[ -d "$payload_app" && -f "$payload_helper" && -f "$payload_daemon" ]]
wattson_cleanup_add_app "$payload_app"
app='/Applications/Wattson.app'
helper='/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper'
daemon='/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist'
wattson_run_timeout 20 /usr/bin/codesign --verify --deep --strict "$app"
wattson_run_timeout 20 /usr/bin/codesign --verify --strict "$helper"
wattson_run_timeout 20 /usr/bin/diff -rq "$payload_app" "$app"
wattson_run_timeout 20 /usr/bin/cmp "$payload_helper" "$helper"
wattson_run_timeout 20 /usr/bin/cmp "$payload_daemon" "$daemon"
/usr/bin/codesign -d --entitlements :- "$app" > "$scratch/entitlements.plist" 2>/dev/null
for binary in "$app/Contents/MacOS/Wattson" "$helper"; do
    /usr/bin/xcrun lipo "$binary" -verify_arch arm64
    /usr/bin/xcrun lipo "$binary" -verify_arch x86_64
done
# These fixed probes exit before creating NSApplication or opening any UI.
wattson_run_timeout 20 "$app/Contents/MacOS/Wattson" --helper-health-probe
wattson_run_timeout 20 "$app/Contents/MacOS/Wattson" --helper-v5-observation-probe > "$scratch/helper-v5.txt"
/usr/bin/grep -Fxq 'helperV5=v5' "$scratch/helper-v5.txt"
cat > "$scratch/verify.py" <<'PY'
import datetime, importlib.util, json, pathlib, plistlib, sys
repo, entitlements, output = map(pathlib.Path, sys.argv[1:4])
module_path = repo / 'design/release-v4.3.23/installation/installation_state.py'
spec = importlib.util.spec_from_file_location('installation_state', module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.check_console_user()
before = json.loads((repo / 'design/system-metric-authority/before-install.json').read_text())
state, settings = module.canonical_state(), module.settings_hashes()
assert state['version'] == state['buildVersion'] == state['receipt']['version'] == '4.3.24'
assert state['bundleIdentifier'] == 'com.leoarrow.wattson'
assert before['packageSHA256'] == sys.argv[4] and before['candidateVersion'] == '4.3.24'
assert settings == before['settingsHashes'], 'Product preferences changed'
assert sum(map(len, settings.values())) == 16
assert plistlib.loads(entitlements.read_bytes()) == plistlib.loads((repo / 'BatteryPowerApp.entitlements').read_bytes())
source = module.run(['git', '-C', str(repo), 'rev-parse', '0ae7ee0^{commit}']).decode().strip()
module.write_new(output, {
    'allPassed': True, 'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'distribution': 'local candidate; not a public release', 'version': '4.3.24',
    'packageSHA256': sys.argv[4], 'sourceCommit': source, 'installedState': state,
    'appPayloadBytesMatch': True, 'helperPayloadBytesMatch': True, 'daemonPayloadBytesMatch': True,
    'appAndHelperSignaturesVerified': True, 'exactProductionEntitlementsVerified': True,
    'bothArchitecturesVerified': True, 'helperHealthPassed': True, 'helperV5Passed': True,
    'settingsHashes': settings, 'settingsRetained': 16,
    'canonicalPopupAcceptance': 'pending; host UI automation unavailable',
})
PY
wattson_run_timeout 30 /usr/bin/python3 "$scratch/verify.py" "$repo" "$scratch/entitlements.plist" "$report_path" "$approved_sha"
