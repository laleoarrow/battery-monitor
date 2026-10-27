#!/bin/bash
# Compare original and fixed local clocks in an extracted History fixture.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
if [[ $# != 1 || -e "$1" || -L "$1" ]]; then
    echo "usage: $0 NEW_OUTPUT_DIRECTORY" >&2
    exit 64
fi
mkdir -p "$1"
OUTPUT_DIR="$(cd "$1" && pwd)"
TART_BIN='/opt/homebrew/bin/tart'
VM_HELPER="$ROOT_DIR/tests/performance/ui_vm.py"
VM_NAME="Wattson-HistoryRetarget-$(/usr/bin/uuidgen)"
export TART_NO_AUTO_PRUNE=1
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/history-retarget-vm.noindex"
RUN_DIR="$(mktemp -d "$ROOT_DIR/.build/history-retarget-vm.noindex/run.XXXXXX")"
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
# Freeze the working source, including newly added files, before booting the VM.
# No host build output or existing app bundle enters the guest.
/usr/bin/tar -czf "$SHARE_DIR/source.tar.gz" -C "$ROOT_DIR" \
    Core MenuBar Popover VERSION BatteryPowerApp.entitlements \
    scripts/verify_interaction.sh scripts/lib/local_cleanup.sh scripts/lib/run_owned.py tests/interaction/main.swift \
    design/release-v5.0.2/diagnostics/history-retarget-timing/guest-probe.sh \
    design/release-v5.0.2/diagnostics/history-retarget-timing/extract.py \
    design/release-v5.0.2/diagnostics/history-retarget-timing/recording.swift \
    design/release-v5.0.2/diagnostics/history-retarget-timing/review.py
/usr/bin/git -C "$ROOT_DIR" rev-parse HEAD > "$OUTPUT_DIR/frozen-head.txt"
/usr/bin/shasum -a 256 "$SHARE_DIR/source.tar.gz" > "$OUTPUT_DIR/source-archive.sha256"
/bin/cp "$VM_HELPER" "$SHARE_DIR/ui_vm.py"
cat > "$SHARE_DIR/guest-run.sh" <<'GUEST'
#!/bin/bash
set -euo pipefail
SHARE='/Volumes/My Shared Files/task'
source '/Volumes/My Shared Files/repo/scripts/lib/local_cleanup.sh'
wattson_cleanup_init
GUEST_PARENT="$HOME/Project/.wattson-ui-vm.noindex"
mkdir -p "$GUEST_PARENT"
RUN_DIR="$(mktemp -d "$GUEST_PARENT/run.XXXXXX")"
wattson_cleanup_add_dir "$RUN_DIR"
/usr/bin/python3 "$SHARE/ui_vm.py" before > "$SHARE/results/guest-before.json"
/usr/bin/sw_vers > "$SHARE/results/system.txt"
xcrun swift --version >> "$SHARE/results/system.txt"
xcrun --show-sdk-version >> "$SHARE/results/system.txt"
mkdir -p "$RUN_DIR/source"
/usr/bin/tar -xzf "$SHARE/source.tar.gz" -C "$RUN_DIR/source"
wattson_run_script "$RUN_DIR/source/design/release-v5.0.2/diagnostics/history-retarget-timing/guest-probe.sh" "$SHARE/results" > "$SHARE/results/probe-owner.log" 2>&1
GUEST
OWNED_VM=1
wattson_run_timeout 300 "$TART_BIN" clone macOS-TestLab-Base "$VM_NAME" > "$OUTPUT_DIR/vm-clone.log" 2>&1
_WATTSON_RUNNER_STARTING=1
/usr/bin/python3 "$ROOT_DIR/scripts/lib/run_owned.py" --timeout 1800 -- "$TART_BIN" run \
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
printf 'HISTORY_RETARGET_VM_READY %s\n' "$VM_NAME"
_WATTSON_RUNNER_STARTING=1
/usr/bin/python3 "$ROOT_DIR/scripts/lib/run_owned.py" --grace 60 --timeout 900 -- \
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
printf 'HISTORY_RETARGET_COMPARISON_AND_CLEANUP_PASSED\n'
