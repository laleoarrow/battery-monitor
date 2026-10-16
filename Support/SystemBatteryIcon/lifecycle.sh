#!/bin/bash
# Shared ownership of this support bundle's scratch directory and child processes.
SUPPORT_SCRATCH=""
SUPPORT_SCRATCH_ROOT=""
SUPPORT_ROOT_CREATED=0
SUPPORT_OUTPUT_PARTIAL=""
# A sentinel keeps macOS's Bash 3.2 compatible with `set -u` on empty arrays.
SUPPORT_CHILDREN=("")

support_cleanup() {
    local status=$?
    trap - EXIT HUP INT TERM
    local pid
    for pid in "${SUPPORT_CHILDREN[@]}"; do
        [[ -n "$pid" ]] || continue
        kill "$pid" 2>/dev/null || true
    done
    if [[ ${#SUPPORT_CHILDREN[@]} -gt 1 ]]; then /bin/sleep 0.2; fi
    for pid in "${SUPPORT_CHILDREN[@]}"; do
        [[ -n "$pid" ]] || continue
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    if [[ -n "$SUPPORT_SCRATCH" ]]; then
        /bin/rm -rf -- "$SUPPORT_SCRATCH"
    fi
    if [[ -n "$SUPPORT_OUTPUT_PARTIAL" ]]; then
        /bin/rm -f -- "$SUPPORT_OUTPUT_PARTIAL"
    fi
    if [[ "$SUPPORT_ROOT_CREATED" == 1 ]]; then
        /bin/rmdir -- "$SUPPORT_SCRATCH_ROOT" 2>/dev/null || true
    fi
    exit "$status"
}

support_begin() {
    SUPPORT_SCRATCH_ROOT=$1
    trap support_cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if [[ ! -d "$SUPPORT_SCRATCH_ROOT" ]]; then
        SUPPORT_ROOT_CREATED=1
        /bin/mkdir -p -- "$SUPPORT_SCRATCH_ROOT"
    fi
    SUPPORT_SCRATCH=$(/usr/bin/mktemp -d "$SUPPORT_SCRATCH_ROOT/run.XXXXXX")
}

support_track() {
    SUPPORT_CHILDREN+=("$1")
}

support_forget() {
    local remaining=("") pid
    for pid in "${SUPPORT_CHILDREN[@]}"; do
        [[ -n "$pid" ]] || continue
        [[ "$pid" == "$1" ]] || remaining+=("$pid")
    done
    SUPPORT_CHILDREN=("${remaining[@]}")
}

support_stop() {
    kill "$1" 2>/dev/null || true
    /bin/sleep 0.2
    kill -KILL "$1" 2>/dev/null || true
    wait "$1" 2>/dev/null || true
    support_forget "$1"
}

# Keep external work owned even when the shell is interrupted during wait.
support_run() {
    "$@" <&0 &
    local pid=$! status=0
    support_track "$pid"
    wait "$pid" || status=$?
    support_forget "$pid"
    return "$status"
}
