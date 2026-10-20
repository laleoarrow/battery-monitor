#!/bin/bash
# Measure fixed production revisions in one disposable ARM GUI VM.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if (( $# < 2 || $# > 4 )) || [[ -e "$1" || -L "$1" ]] || { (( $# == 4 )) && [[ "${3:-}" != --diagnostic-patch ]]; }; then
    echo "usage: $0 NEW_OUTPUT_DIR BASELINE_REF [CANDIDATE_REF | --diagnostic-patch PATCH]" >&2
    exit 64
fi
OUTPUT_DIR="$1"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
BASELINE_REF="$2"
CANDIDATE_REF="${3:-}"
DIAGNOSTIC_PATCH=''
if [[ "${3:-}" == --diagnostic-patch ]]; then
    [[ $# == 4 && -f "$4" ]] || exit 64
    DIAGNOSTIC_PATCH="$4"
    CANDIDATE_REF=''
fi
TART_BIN='/opt/homebrew/bin/tart'
VM_HELPER="$ROOT_DIR/tests/performance/ui_vm.py"
VM_NAME="Wattson-UILatency-$(/usr/bin/uuidgen)"
export TART_NO_AUTO_PRUNE=1
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/ui-vm.noindex"
RUN_DIR="$(mktemp -d "$ROOT_DIR/.build/ui-vm.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$RUN_DIR"
SHARE_DIR="$RUN_DIR/share"
mkdir -p "$SHARE_DIR/results"
OWNED_VM=0
VM_RUNNER_PID=''
return_status() { return "$1"; }
finish() {
    local status=$? state=''
    trap - EXIT
    trap '' HUP INT TERM
    set +e
    if [[ -n "${_WATTSON_RUNNER_PID:-}" ]]; then
        kill -TERM "$_WATTSON_RUNNER_PID" 2>/dev/null
        wait "$_WATTSON_RUNNER_PID" 2>/dev/null
        _WATTSON_RUNNER_PID=''
    fi
    if [[ "$OWNED_VM" == 1 ]]; then
        wattson_run_timeout 10 "$TART_BIN" list --format json > "$OUTPUT_DIR/vms-cleanup-current.json" || status=1
        state="$(/usr/bin/python3 "$VM_HELPER" state "$VM_NAME" "$OUTPUT_DIR/vms-cleanup-current.json")" || status=1
        if [[ "$state" == running ]]; then
            wattson_run_timeout 20 "$TART_BIN" stop "$VM_NAME" --timeout 10 >> "$OUTPUT_DIR/vm-cleanup.log" 2>&1 || status=1
        fi
        if [[ -n "$VM_RUNNER_PID" ]]; then
            kill -TERM "$VM_RUNNER_PID" 2>/dev/null
            wait "$VM_RUNNER_PID" 2>/dev/null
            VM_RUNNER_PID=''
        fi
        wattson_run_timeout 10 "$TART_BIN" list --format json > "$OUTPUT_DIR/vms-after-stop.json" || status=1
        state="$(/usr/bin/python3 "$VM_HELPER" state "$VM_NAME" "$OUTPUT_DIR/vms-after-stop.json")" || status=1
        if [[ "$state" == stopped ]]; then
            wattson_run_timeout 30 "$TART_BIN" delete "$VM_NAME" >> "$OUTPUT_DIR/vm-cleanup.log" 2>&1 || status=1
        elif [[ "$state" != missing ]]; then
            status=1
        fi
        wattson_run_timeout 10 "$TART_BIN" list --format json > "$OUTPUT_DIR/vms-after-cleanup.json" || status=1
        /usr/bin/python3 "$VM_HELPER" after "$VM_NAME" "$OUTPUT_DIR/vms-before.json" "$OUTPUT_DIR/vms-after-cleanup.json" > "$OUTPUT_DIR/vm-cleanup-summary.json" || status=1
    fi
    /bin/cp -R "$SHARE_DIR/results/." "$OUTPUT_DIR/" || status=1
    printf '%s\n' "$status" > "$OUTPUT_DIR/exit-code.txt"
    return_status "$status"
    _wattson_cleanup
}
trap finish EXIT
wattson_run_timeout 10 "$TART_BIN" list --format json > "$OUTPUT_DIR/vms-before.json"
/usr/bin/python3 "$VM_HELPER" preflight "$VM_NAME" "$OUTPUT_DIR/vms-before.json"
/usr/bin/python3 "$VM_HELPER" pack "$ROOT_DIR" "$SHARE_DIR" "$BASELINE_REF" "$CANDIDATE_REF" "$DIAGNOSTIC_PATCH"
/bin/cp "$SHARE_DIR/manifest.json" "$OUTPUT_DIR/manifest.json"
/bin/cp "$ROOT_DIR/tests/performance/ui-vm-guest.sh" "$SHARE_DIR/guest-run.sh"
/bin/cp "$VM_HELPER" "$SHARE_DIR/ui_vm.py"
# Record ownership before clone so an interrupted/partial clone is also removed.
OWNED_VM=1
wattson_run_timeout 300 "$TART_BIN" clone macOS-TestLab-Base "$VM_NAME" > "$OUTPUT_DIR/vm-clone.log" 2>&1
_WATTSON_RUNNER_STARTING=1
/usr/bin/python3 "$ROOT_DIR/scripts/lib/run_owned.py" --timeout 4500 -- "$TART_BIN" run \
    --no-graphics --no-audio --no-clipboard --dir "repo:$ROOT_DIR:ro" \
    --dir "task:$SHARE_DIR" "$VM_NAME" > "$OUTPUT_DIR/vm-run.log" 2>&1 &
VM_RUNNER_PID=$!
_wattson_runner_registered
ready=0
for attempt in {1..45}; do
    if wattson_run_timeout 15 "$TART_BIN" exec "$VM_NAME" /bin/bash -c \
        'test -d "/Volumes/My Shared Files/task" && /usr/bin/pgrep -x WindowServer >/dev/null' \
        > "$OUTPUT_DIR/readiness.log" 2>&1; then ready=1; break; fi
    kill -0 "$VM_RUNNER_PID" 2>/dev/null || exit 1
    sleep 2
done
[[ "$ready" == 1 ]]
printf 'UI_MEASUREMENT_VM_READY %s\n' "$VM_NAME"
# The lifecycle child receives 60 seconds to finish its own cleanup on timeout.
_WATTSON_RUNNER_STARTING=1
/usr/bin/python3 "$ROOT_DIR/scripts/lib/run_owned.py" --grace 60 --timeout 3900 -- \
    "$TART_BIN" exec "$VM_NAME" /bin/bash '/Volumes/My Shared Files/task/guest-run.sh' \
    > "$OUTPUT_DIR/guest.log" 2> "$OUTPUT_DIR/guest.err" &
_WATTSON_RUNNER_PID=$!
_wattson_runner_registered
GUEST_STATUS=0
wait "$_WATTSON_RUNNER_PID" || GUEST_STATUS=$?
_WATTSON_RUNNER_PID=''
AUDIT_STATUS=0
wattson_run_timeout 60 "$TART_BIN" exec "$VM_NAME" /usr/bin/python3 \
    '/Volumes/My Shared Files/task/ui_vm.py' audit \
    > "$OUTPUT_DIR/guest-audit.log" 2> "$OUTPUT_DIR/guest-audit.err" || AUDIT_STATUS=$?
[[ "$GUEST_STATUS" == 0 ]] || exit "$GUEST_STATUS"
[[ "$AUDIT_STATUS" == 0 ]] || exit "$AUDIT_STATUS"
printf 'UI_MEASUREMENT_AND_GUEST_CLEANUP_PASSED\n'
