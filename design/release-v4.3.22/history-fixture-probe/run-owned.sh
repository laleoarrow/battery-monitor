#!/bin/bash
# Freeze the bounded diagnostic and optionally reuse its disposable VM for gates.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
scripts="$repo/design/release-v4.3.22/history-fixture-probe"
native="$repo/design/release-v4.3.22/native"
source_ref='8300cabcb5859fcc74c3ff613a2c530a47c01f30'
if [[ "$#" -lt 1 || "$#" -gt 2 || "$1" != "$repo/"* || -e "$1" ]]; then
    echo 'usage: run-owned.sh NEW_ABSOLUTE_OUTPUT_DIRECTORY_UNDER_PROJECT [FULL_GATE_FROZEN_COMMIT]' >&2
    exit 64
fi
if [[ "$#" == 2 ]]; then
    [[ "$2" =~ ^[0-9a-f]{40}$ ]]
    [[ "$(git -C "$repo" rev-parse "$2^{commit}")" == "$2" ]]
fi
[[ -s "$scripts/probe.swift" ]]
[[ "$(git -C "$repo" rev-parse "$source_ref^{commit}")" == "$source_ref" ]]
review="$1"
mkdir -p "$review" "$repo/.build/history-fixture-probe.noindex"
if [[ "$#" == 2 ]]; then printf '%s\n' "$2" > "$review/full-gate-source-commit.txt"; fi
export TART_NO_AUTO_PRUNE=1
export WATTSON_QA_VM_NAME="Wattson-History-Fixture-$(/usr/bin/uuidgen | cut -c1-8)"
vm="$WATTSON_QA_VM_NAME"
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
snapshot="$(mktemp -d "$repo/.build/history-fixture-probe.noindex/snapshot.XXXXXX")"
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
        state="$(python3 "$snapshot/vm-state.py" state "$review/vms-cleanup-current.json")" || status=1
        if [[ "$state" == running ]]; then wattson_run_timeout 45 tart stop "$vm" --timeout 20 >> "$review/vm-cleanup.log" 2>&1 || status=1; fi
        if [[ -n "$vm_runner_pid" ]]; then
            if kill -0 "$vm_runner_pid" 2>/dev/null; then kill -TERM "$vm_runner_pid" 2>/dev/null; fi
            wait "$vm_runner_pid" 2>/dev/null
            vm_runner_pid=''
        fi
        tart list --format json > "$review/vms-after-stop.json" || status=1
        state="$(python3 "$snapshot/vm-state.py" state "$review/vms-after-stop.json")" || status=1
        if [[ "$state" == stopped ]]; then wattson_run_timeout 45 tart delete "$vm" >> "$review/vm-cleanup.log" 2>&1 || status=1; elif [[ "$state" != missing ]]; then status=1; fi
        tart list --format json > "$review/vms-after-cleanup.json" || status=1
        python3 "$snapshot/vm-state.py" after "$review/vms-before.json" "$review/vms-after-cleanup.json" > "$review/vm-cleanup-summary.json" 2> "$review/vm-cleanup-summary.err" || status=1
    fi
    (return_status "$status"; _wattson_cleanup)
    status=$?
    if [[ "$status" != 0 && -f "$review/full-native-gate-status.txt" ]]; then
        case "$(cat "$review/full-native-gate-status.txt")" in
            freezing|running|awaiting-commit) printf 'failed-or-interrupted\n' > "$review/full-native-gate-status.txt" ;;
        esac
    fi
    printf '%s\n' "$status" > "$review/exit-code.txt"
    exit "$status"
}
trap finish EXIT
run_with_grace() {
    local seconds="$1" status=0
    shift
    _WATTSON_RUNNER_STARTING=1
    /usr/bin/python3 "$snapshot/run_owned.py" --grace 65 --timeout "$seconds" -- "$@" &
    _WATTSON_RUNNER_PID=$!
    _wattson_runner_registered
    wait "$_WATTSON_RUNNER_PID" || status=$?
    _WATTSON_RUNNER_PID=''
    return "$status"
}
freeze_source() {
    local ref="$1" destination="$2"
    mkdir -p "$destination"
    wattson_run_timeout 60 git -C "$repo" archive --format=tar.gz "$ref" Package.swift VERSION BatteryPowerApp.entitlements Core MenuBar Popover Helper HelperV5 scripts tests design/icon/in-app-logo design/process-force-quit/native/display-probe.swift > "$destination/source.tar.gz"
    shasum -a 256 "$destination/source.tar.gz" | awk '{print $1}' > "$destination/source.sha256"
    python3 "$snapshot/source-manifest.py" archive "$destination/source.tar.gz" "$destination/frozen-source-inputs.sha256"
    git -C "$repo" show "$ref:scripts/lib/local_cleanup.sh" > "$destination/local_cleanup.sh"
    git -C "$repo" show "$ref:scripts/lib/run_owned.py" > "$destination/run_owned.py"
}
cp "$scripts/guest-run.sh" "$scripts/audit-guest.py" "$scripts/source-manifest.py" "$scripts/vm-state.py" "$scripts/probe.swift" "$snapshot/"
mkdir "$snapshot/native-harness"
cp "$native/guest-run.sh" "$native/audit-guest.py" "$snapshot/native-harness/"
tart list --format json > "$review/vms-before.json"
python3 "$snapshot/vm-state.py" preflight "$review/vms-before.json"
printf '%s\n' "$vm" > "$review/owned-vm-name.txt"
printf '%s\n' "$source_ref" > "$review/frozen-source-commit.txt"
freeze_source "$source_ref" "$snapshot"
cp "$snapshot/source.sha256" "$snapshot/frozen-source-inputs.sha256" "$review/"
shasum -a 256 "$snapshot/probe.swift" | awk '{print $1}' > "$snapshot/probe.sha256"
cp "$snapshot/probe.sha256" "$review/probe.sha256"
shasum -a 256 "$scripts/run-owned.sh" "$snapshot"/*.sh "$snapshot"/*.py "$snapshot/probe.swift" "$snapshot/native-harness"/* "$repo/scripts/lib/local_cleanup.sh" "$repo/scripts/lib/run_owned.py" > "$review/harness-inputs.sha256"
owned_vm=1
wattson_run_timeout 300 tart clone macOS-TestLab-Base "$vm" > "$review/vm-clone.log" 2>&1
printf 'OWNED_VM_CREATED %s\n' "$vm"
_WATTSON_RUNNER_STARTING=1
/usr/bin/python3 "$snapshot/run_owned.py" --timeout 4200 -- tart run --no-graphics --no-audio --no-clipboard --dir "review:$review" --dir "snapshot:$snapshot:ro" "$vm" > "$review/vm-run.log" 2>&1 &
vm_runner_pid=$!
_wattson_runner_registered
ready=0
for attempt in {1..45}; do
    if wattson_run_timeout 15 tart exec "$vm" /bin/bash -c 'test -d "/Volumes/My Shared Files/review" && /usr/bin/pgrep -x WindowServer >/dev/null' > "$review/readiness.log" 2>&1; then ready=1; break; fi
    kill -0 "$vm_runner_pid" || exit 1
    sleep 2
done
[[ "$ready" == 1 ]]
printf 'OWNED_VM_READY %s\n' "$vm"
diagnostic_status=0
run_with_grace 850 tart exec "$vm" /bin/bash '/Volumes/My Shared Files/snapshot/guest-run.sh' > "$review/guest.log" 2> "$review/guest.err" || diagnostic_status=$?
printf '%s\n' "$diagnostic_status" > "$review/diagnostic-exit-code.txt"
printf 'DIAGNOSTIC_EXIT_STATUS %s\n' "$diagnostic_status"
audit_status=0
wattson_run_timeout 70 tart exec "$vm" /usr/bin/python3 '/Volumes/My Shared Files/snapshot/audit-guest.py' '/Volumes/My Shared Files/review/results' > "$review/resource-audit.log" 2> "$review/resource-audit.err" || audit_status=$?
printf '%s\n' "$audit_status" > "$review/diagnostic-audit-exit-code.txt"
printf 'DIAGNOSTIC_RESOURCE_AUDIT_EXIT_STATUS %s\n' "$audit_status"
[[ "$diagnostic_status" == 0 ]] || exit "$diagnostic_status"
[[ "$audit_status" == 0 ]] || exit "$audit_status"
printf 'DIAGNOSTIC_AND_CLEANUP_CHECKS_PASSED\n'
printf 'awaiting-commit\n' > "$review/full-native-gate-status.txt"
for attempt in {1..120}; do
    [[ ! -e "$review/full-gate-source-commit.txt" ]] || break
    kill -0 "$vm_runner_pid" || exit 1
    sleep 1
done
if [[ ! -e "$review/full-gate-source-commit.txt" ]]; then
    printf 'not-requested-within-120-seconds\n' > "$review/full-native-gate-status.txt"
    exit 0
fi
printf 'freezing\n' > "$review/full-native-gate-status.txt"
full_ref="$(cat "$review/full-gate-source-commit.txt")"
[[ "$full_ref" =~ ^[0-9a-f]{40}$ ]]
[[ "$(git -C "$repo" rev-parse "$full_ref^{commit}")" == "$full_ref" ]]
full_snapshot="$snapshot/full-gate"
full_review="$review/full-native-gate"
mkdir "$full_review"
printf '%s\n' "$full_ref" > "$full_review/frozen-source-commit.txt"
freeze_source "$full_ref" "$full_snapshot"
cp "$snapshot/source-manifest.py" "$snapshot/native-harness/audit-guest.py" "$full_snapshot/"
python3 - "$snapshot/native-harness/guest-run.sh" "$full_snapshot/guest-run.sh" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
for old, new in [
    ("share='/Volumes/My Shared Files/review'", "share='/Volumes/My Shared Files/review/full-native-gate'"),
    ("snapshot='/Volumes/My Shared Files/snapshot'", "snapshot='/Volumes/My Shared Files/snapshot/full-gate'"),
]:
    assert text.count(old) == 1, old
    text = text.replace(old, new)
pathlib.Path(sys.argv[2]).write_text(text)
PY
cp "$full_snapshot/source.sha256" "$full_snapshot/frozen-source-inputs.sha256" "$full_review/"
shasum -a 256 "$full_snapshot"/*.sh "$full_snapshot"/*.py > "$full_review/harness-inputs.sha256"
printf 'running\n' > "$review/full-native-gate-status.txt"
full_status=0
run_with_grace 2400 tart exec "$vm" /bin/bash '/Volumes/My Shared Files/snapshot/full-gate/guest-run.sh' > "$full_review/guest.log" 2> "$full_review/guest.err" || full_status=$?
printf '%s\n' "$full_status" > "$full_review/guest-exit-code.txt"
printf 'FULL_NATIVE_GATE_EXIT_STATUS %s\n' "$full_status"
full_audit_status=0
wattson_run_timeout 70 tart exec "$vm" /usr/bin/python3 '/Volumes/My Shared Files/snapshot/full-gate/audit-guest.py' '/Volumes/My Shared Files/review/full-native-gate/results' > "$full_review/resource-audit.log" 2> "$full_review/resource-audit.err" || full_audit_status=$?
printf '%s\n' "$full_audit_status" > "$full_review/audit-exit-code.txt"
printf 'FULL_NATIVE_RESOURCE_AUDIT_EXIT_STATUS %s\n' "$full_audit_status"
if [[ "$full_status" != 0 || "$full_audit_status" != 0 ]]; then
    printf 'failed\n' > "$review/full-native-gate-status.txt"
    [[ "$full_status" == 0 ]] || exit "$full_status"
    exit "$full_audit_status"
fi
printf 'passed\n' > "$review/full-native-gate-status.txt"
printf 'ALL_DIAGNOSTIC_NATIVE_AND_CLEANUP_CHECKS_PASSED\n'
