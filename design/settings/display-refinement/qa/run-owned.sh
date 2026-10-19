#!/bin/bash
# Freeze both renderers; own only one new VM, one source share and its processes.
set -euo pipefail
unset PYTHONOPTIMIZE
export PYTHONDONTWRITEBYTECODE=1
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
qa="$repo/design/settings/display-refinement/qa"
helpers="$repo/design/performance-hardening-20261019/focus-native"
if [[ "$#" != 2 || "$2" != "$repo/"* || -e "$2" ]]; then
    echo 'usage: run-owned.sh FROZEN_COMMIT NEW_ABSOLUTE_EVIDENCE_DIRECTORY_UNDER_PROJECT' >&2
    exit 64
fi
source_ref="$(git -C "$repo" rev-parse "$1^{commit}")"
before_ref="$(git -C "$repo" rev-parse 'b079f29^{commit}')"
review="$2"
mkdir -p "$review" "$repo/.build/display-settings.noindex"
export TART_NO_AUTO_PRUNE=1
export WATTSON_QA_VM_NAME="Wattson-Display-QA-$(/usr/bin/uuidgen | cut -c1-8)"
vm="$WATTSON_QA_VM_NAME"
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
snapshot="$(mktemp -d "$repo/.build/display-settings.noindex/snapshot.XXXXXX")"
wattson_cleanup_add_dir "$snapshot"
owned_vm=0
vm_runner_pid=''
return_status() { return "$1"; }
finish() {
    local status=$? state=''
    trap - EXIT
    trap '' HUP INT TERM
    set +e
    if [[ -n "${_WATTSON_RUNNER_PID:-}" ]]; then kill -TERM "$_WATTSON_RUNNER_PID" 2>/dev/null; wait "$_WATTSON_RUNNER_PID" 2>/dev/null; _WATTSON_RUNNER_PID=''; fi
    if [[ "$owned_vm" == 1 ]]; then
        tart list --format json > "$review/vms-cleanup-current.json" || status=1
        state="$(python3 "$helpers/vm-state.py" state "$review/vms-cleanup-current.json")" || status=1
        if [[ "$state" == running ]]; then wattson_run_timeout 45 tart stop "$vm" --timeout 20 >> "$review/vm-cleanup.log" 2>&1 || status=1; fi
        if [[ -n "$vm_runner_pid" ]]; then
            if kill -0 "$vm_runner_pid" 2>/dev/null; then kill -TERM "$vm_runner_pid" 2>/dev/null; fi
            wait "$vm_runner_pid" 2>/dev/null
            vm_runner_pid=''
        fi
        tart list --format json > "$review/vms-after-stop.json" || status=1
        state="$(python3 "$helpers/vm-state.py" state "$review/vms-after-stop.json")" || status=1
        if [[ "$state" == stopped ]]; then wattson_run_timeout 45 tart delete "$vm" >> "$review/vm-cleanup.log" 2>&1 || status=1; elif [[ "$state" != missing ]]; then status=1; fi
        tart list --format json > "$review/vms-after-cleanup.json" || status=1
        python3 "$helpers/vm-state.py" after "$review/vms-before.json" "$review/vms-after-cleanup.json" > "$review/vm-cleanup-summary.json" 2> "$review/vm-cleanup-summary.err" || status=1
    fi
    python3 "$qa/preserve-canonical.py" verify "$review/canonical-before.json" "$review/canonical-after.json" || status=1
    printf '%s\n' "$status" > "$review/exit-code.txt"
    return_status "$status"
    _wattson_cleanup
}
trap finish EXIT
python3 "$qa/preserve-canonical.py" record "$review/canonical-before.json"
tart list --format json > "$review/vms-before.json"
python3 "$helpers/vm-state.py" preflight "$review/vms-before.json"
printf '%s\n' "$vm" > "$review/owned-vm-name.txt"
printf 'before %s\nafter %s\n' "$before_ref" "$source_ref" > "$review/frozen-source-commits.txt"
for phase in before after; do
    ref="$source_ref"
    [[ "$phase" != before ]] || ref="$before_ref"
    wattson_run_timeout 60 git -C "$repo" archive --format=tar.gz "$ref" Package.swift VERSION BatteryPowerApp.entitlements Core MenuBar Popover Helper HelperV5 scripts tests design/icon/in-app-logo > "$snapshot/$phase.tar.gz"
    shasum -a 256 "$snapshot/$phase.tar.gz" | awk '{print $1}' > "$snapshot/$phase.sha256"
    python3 "$helpers/source-manifest.py" archive "$snapshot/$phase.tar.gz" "$snapshot/$phase-inputs.sha256"
    cp "$snapshot/$phase.sha256" "$snapshot/$phase-inputs.sha256" "$review/"
done
for file in guest-run.sh capture-compositor.py audit-guest.py; do
    git -C "$repo" show "$source_ref:design/settings/display-refinement/qa/$file" > "$snapshot/$file"
done
git -C "$repo" show "$source_ref:tests/visual/capture_display_settings.swift" > "$snapshot/capture_display_settings.swift"
git -C "$repo" show "$source_ref:scripts/lib/local_cleanup.sh" > "$snapshot/local_cleanup.sh"
git -C "$repo" show "$source_ref:scripts/lib/run_owned.py" > "$snapshot/run_owned.py"
cp "$helpers/source-manifest.py" "$snapshot/"
shasum -a 256 "$snapshot"/* "$qa/run-owned.sh" "$qa/preserve-canonical.py" "$helpers/vm-state.py" > "$review/harness-inputs.sha256"
owned_vm=1
wattson_run_timeout 300 tart clone macOS-TestLab-Base "$vm" > "$review/vm-clone.log" 2>&1
_WATTSON_RUNNER_STARTING=1
/usr/bin/python3 "$repo/scripts/lib/run_owned.py" --timeout 2000 -- tart run --no-graphics --no-audio --no-clipboard --dir "review:$review" --dir "snapshot:$snapshot:ro" "$vm" > "$review/vm-run.log" 2>&1 &
vm_runner_pid=$!
_wattson_runner_registered
ready=0
for attempt in {1..45}; do
    if wattson_run_timeout 15 tart exec "$vm" /bin/bash -c 'test -d "/Volumes/My Shared Files/review" && /usr/bin/pgrep -x WindowServer >/dev/null' > "$review/readiness.log" 2>&1; then ready=1; break; fi
    kill -0 "$vm_runner_pid" || exit 1
    sleep 2
done
[[ "$ready" == 1 ]]
printf 'OWNED_DISPLAY_VM_READY %s\n' "$vm"
guest_status=0
_WATTSON_RUNNER_STARTING=1
/usr/bin/python3 "$repo/scripts/lib/run_owned.py" --grace 65 --timeout 1800 -- tart exec "$vm" /bin/bash '/Volumes/My Shared Files/snapshot/guest-run.sh' > "$review/guest.log" 2> "$review/guest.err" &
_WATTSON_RUNNER_PID=$!
_wattson_runner_registered
wait "$_WATTSON_RUNNER_PID" || guest_status=$?
_WATTSON_RUNNER_PID=''
audit_status=0
wattson_run_timeout 70 tart exec "$vm" /usr/bin/python3 '/Volumes/My Shared Files/snapshot/audit-guest.py' '/Volumes/My Shared Files/review/results' > "$review/resource-audit.log" 2> "$review/resource-audit.err" || audit_status=$?
[[ "$guest_status" == 0 ]] || exit "$guest_status"
[[ "$audit_status" == 0 ]] || exit "$audit_status"
# Tart may return zero even when the remote shell exits early. Require the
# actual workload markers and every expected capture before accepting the run.
python3 - "$review" <<'PY'
import json,pathlib,sys
review=pathlib.Path(sys.argv[1]);results=review/'results';checks={}
checks['guestCompleted']='DISPLAY_SETTINGS_CAPTURE_AND_NATIVE_CONTRACT_PASSED' in (review/'guest.log').read_text()
contract=results/'settings-contract.log';errors=results/'settings-contract.err'
checks['nativeAssertionsCompleted']=contract.exists() and 'all assertions complete' in contract.read_text()
checks['unittestPassed']=errors.exists() and '\nOK\n' in errors.read_text()
for name,count in [('before-baseline',4),('after-baseline',8),('after-high-contrast',8),('after-reduce-transparency',8),('after-native-selected',2)]:
    directory=results/name;path=directory/'capture-results.json'
    report=json.loads(path.read_text()) if path.is_file() else {}
    checks[name]=report.get('allPassed') is True and report.get('captureCount')==count and len(list(directory.glob('*.png')))==count and len(list(directory.glob('*-geometry.json')))==count
for phase in ['before','after']:
    for edge in ['before','after']:
        path=results/f'{phase}-source-{edge}.json'
        checks[f'{phase}-source-{edge}']=path.is_file() and json.loads(path.read_text()).get('allPassed') is True
report={'schema':1,'allPassed':all(checks.values()),'checks':checks}
(review/'gate-results.json').write_text(json.dumps(report,indent=2)+'\n')
assert report['allPassed'],checks
PY
printf 'DISPLAY_NATIVE_QA_AND_CLEANUP_PASSED\n'
