#!/bin/bash
# Creates, verifies, stops, and deletes only its own disposable GUI VM.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
scripts="$repo/design/process-force-quit/native"
if [[ "$#" != 1 || "$1" != "$repo/"* || -e "$1" ]]; then
    echo 'usage: run-owned.sh NEW_ABSOLUTE_OUTPUT_DIRECTORY_UNDER_PROJECT' >&2
    exit 64
fi
review="$1"
mkdir -p "$review" "$repo/.build/process-force-quit-qa.noindex"
export TART_NO_AUTO_PRUNE=1
export WATTSON_QA_VM_NAME="Wattson-Force-Quit-$(/usr/bin/uuidgen | cut -c1-8)"
vm="$WATTSON_QA_VM_NAME"
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
snapshot="$(mktemp -d "$repo/.build/process-force-quit-qa.noindex/snapshot.XXXXXX")"
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
        state="$(python3 "$scripts/vm-state.py" state "$review/vms-cleanup-current.json")" || status=1
        if [[ "$state" == running ]]; then wattson_run_timeout 45 tart stop "$vm" --timeout 20 >> "$review/vm-cleanup.log" 2>&1 || status=1; fi
        if [[ -n "$vm_runner_pid" ]]; then
            if kill -0 "$vm_runner_pid" 2>/dev/null; then kill -TERM "$vm_runner_pid" 2>/dev/null; fi
            wait "$vm_runner_pid" 2>/dev/null
            vm_runner_pid=''
        fi
        tart list --format json > "$review/vms-after-stop.json" || status=1
        state="$(python3 "$scripts/vm-state.py" state "$review/vms-after-stop.json")" || status=1
        if [[ "$state" == stopped ]]; then wattson_run_timeout 45 tart delete "$vm" >> "$review/vm-cleanup.log" 2>&1 || status=1; elif [[ "$state" != missing ]]; then status=1; fi
        tart list --format json > "$review/vms-after-cleanup.json" || status=1
        python3 "$scripts/vm-state.py" after "$review/vms-before.json" "$review/vms-after-cleanup.json" > "$review/vm-cleanup-summary.json" 2> "$review/vm-cleanup-summary.err" || status=1
    fi
    printf '%s\n' "$status" > "$review/exit-code.txt"
    return_status "$status"
    _wattson_cleanup
}
trap finish EXIT
tart list --format json > "$review/vms-before.json"
python3 "$scripts/vm-state.py" preflight "$review/vms-before.json"
printf '%s\n' "$vm" > "$review/owned-vm-name.txt"
wattson_run_timeout 30 tar -czf "$snapshot/source.tar.gz" -C "$repo" Package.swift VERSION BatteryPowerApp.entitlements Core MenuBar Popover Helper HelperV5 design/icon/in-app-logo tests/visual/capture_process_force_quit.swift tests/visual/capture_glass_shadow.c tests/visual/capture_glass_shadow.h design/process-force-quit/native/display-probe.swift design/process-force-quit/native/alert-probe.swift design/process-force-quit/native/root-worker-probe.swift
shasum -a 256 "$snapshot/source.tar.gz" | awk '{print $1}' > "$snapshot/source.sha256"
cp "$snapshot/source.sha256" "$review/source.sha256"
shasum -a 256 "$repo"/Core/*.swift "$repo"/MenuBar/*.swift "$repo"/Popover/*.swift "$repo"/Helper/*.swift "$repo"/HelperV5/*.swift "$repo/Package.swift" "$repo/BatteryPowerApp.entitlements" > "$review/frozen-production-inputs.sha256"
shasum -a 256 "$scripts"/*.sh "$scripts"/*.py "$scripts"/*.swift "$repo/tests/visual/capture_process_force_quit.swift" "$repo/scripts/lib/local_cleanup.sh" "$repo/scripts/lib/run_owned.py" > "$review/harness-inputs.sha256"
owned_vm=1
wattson_run_timeout 300 tart clone macOS-TestLab-Base "$vm" > "$review/vm-clone.log" 2>&1
printf 'OWNED_VM_CREATED %s\n' "$vm"
/usr/bin/python3 "$repo/scripts/lib/run_owned.py" --timeout 1200 -- tart run --no-graphics --no-audio --no-clipboard --dir "repo:$repo:ro" --dir "review:$review" --dir "snapshot:$snapshot:ro" "$vm" > "$review/vm-run.log" 2>&1 &
vm_runner_pid=$!
ready=0
for attempt in {1..45}; do
    if wattson_run_timeout 15 tart exec "$vm" /bin/bash -c 'test -d "/Volumes/My Shared Files/review" && /usr/bin/pgrep -x WindowServer >/dev/null' > "$review/readiness.log" 2>&1; then ready=1; break; fi
    kill -0 "$vm_runner_pid" || exit 1
    sleep 2
done
[[ "$ready" == 1 ]]
printf 'OWNED_VM_READY %s\n' "$vm"
guest_status=0
wattson_run_timeout 900 tart exec "$vm" /bin/bash '/Volumes/My Shared Files/repo/design/process-force-quit/native/guest-run.sh' > "$review/guest.log" 2> "$review/guest.err" || guest_status=$?
printf 'GUEST_EXIT_STATUS %s\n' "$guest_status"
audit_status=0
wattson_run_timeout 70 tart exec "$vm" /usr/bin/python3 '/Volumes/My Shared Files/repo/design/process-force-quit/native/audit-guest.py' '/Volumes/My Shared Files/review/results' > "$review/resource-audit.log" 2> "$review/resource-audit.err" || audit_status=$?
printf 'RESOURCE_AUDIT_EXIT_STATUS %s\n' "$audit_status"
[[ "$guest_status" == 0 ]] || exit "$guest_status"
[[ "$audit_status" == 0 ]] || exit "$audit_status"
printf 'ALL_NATIVE_AND_CLEANUP_CHECKS_PASSED\n'
