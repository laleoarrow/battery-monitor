#!/bin/bash
# Source this file, initialize once, then register only this invocation's paths.
_WATTSON_CLEANUP_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A signal must not enter cleanup between runner spawn and PID publication.
_wattson_signal() {
    if [[ "$_WATTSON_RUNNER_STARTING" == 1 ]]; then
        [[ "$_WATTSON_PENDING_SIGNAL" != 0 ]] || _WATTSON_PENDING_SIGNAL=$1
    else
        exit "$1"
    fi
}

_wattson_runner_registered() {
    _WATTSON_RUNNER_STARTING=0
    if [[ "${_WATTSON_PENDING_SIGNAL:-0}" != 0 ]]; then
        exit "$_WATTSON_PENDING_SIGNAL"
    fi
}

wattson_run() {
    _WATTSON_RUNNER_STARTING=1
    /usr/bin/python3 "$_WATTSON_CLEANUP_LIB/run_owned.py" -- "$@" &
    _WATTSON_RUNNER_PID=$!
    _wattson_runner_registered
    local status=0
    wait "$_WATTSON_RUNNER_PID" || status=$?
    _WATTSON_RUNNER_PID=""
    return "$status"
}

wattson_run_timeout() {
    local seconds="$1"
    shift
    _WATTSON_RUNNER_STARTING=1
    /usr/bin/python3 "$_WATTSON_CLEANUP_LIB/run_owned.py" --timeout "$seconds" -- "$@" &
    _WATTSON_RUNNER_PID=$!
    _wattson_runner_registered
    local status=0
    wait "$_WATTSON_RUNNER_PID" || status=$?
    _WATTSON_RUNNER_PID=""
    return "$status"
}

# Lifecycle scripts need time to finish their own unmount/unregister traps.
# Their compiler/tool children still use the ordinary two-second grace period.
wattson_run_script() {
    _WATTSON_RUNNER_STARTING=1
    /usr/bin/python3 "$_WATTSON_CLEANUP_LIB/run_owned.py" --grace 60 -- /bin/bash "$@" &
    _WATTSON_RUNNER_PID=$!
    _wattson_runner_registered
    local status=0
    wait "$_WATTSON_RUNNER_PID" || status=$?
    _WATTSON_RUNNER_PID=""
    return "$status"
}

wattson_unregister_app() {
    local app="$1"
    local registrar="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    [[ -d "$app" && ! -L "$app" && -x "$registrar" ]] || return 0
    # Unregistered bundles return nonzero too; never register them to check.
    local status=0
    wattson_run_timeout 10 "$registrar" -u "$app" >/dev/null 2>&1 || status=$?
    if [[ "$status" == 124 ]]; then
        echo "Cleanup timed out unregistering app: $app" >&2
        return 1
    fi
}

_wattson_is_mounted() {
    local mounts
    mounts="$(/sbin/mount)" || return 0
    /usr/bin/grep -Fq " on $1 (" <<< "$mounts"
}

_wattson_directory_has_mount() {
    local mounts line mounted_path
    mounts="$(/sbin/mount)" || return 0
    while IFS= read -r line; do
        mounted_path="${line#* on }"
        mounted_path="${mounted_path% (*}"
        case "$mounted_path/" in "$1/"*) return 0 ;; esac
    done <<< "$mounts"
    return 1
}

wattson_detach() {
    local mountpoint="$1"
    local attempt
    _wattson_is_mounted "$mountpoint" || return 0
    for attempt in 1 2 3; do
        wattson_run_timeout 10 /usr/bin/hdiutil detach "$mountpoint" >/dev/null 2>&1 || true
        _wattson_is_mounted "$mountpoint" || return 0
    done
    echo "Cleanup could not detach owned mount: $mountpoint" >&2
    return 1
}

wattson_cleanup_add_dir() { _WATTSON_CLEANUP_DIRS+=("$1"); }
wattson_cleanup_add_app() { _WATTSON_CLEANUP_APPS+=("$1"); }
wattson_cleanup_add_mount() { _WATTSON_CLEANUP_MOUNTS+=("$1"); }
wattson_cleanup_add_executable() { _WATTSON_CLEANUP_EXECUTABLES+=("$1"); }
wattson_cleanup_add_defaults() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]] || return 2
    _WATTSON_CLEANUP_DEFAULTS+=("$1");
}
wattson_cleanup_add_container() {
    local identifier="$1"
    [[ "$identifier" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]] || return 2
    local container="$HOME/Library/Containers/$identifier"
    if [[ ! -e "$container" && ! -L "$container" ]]; then
        wattson_cleanup_add_dir "$container"
    fi
    local application_scripts="$HOME/Library/Application Scripts/$identifier"
    if [[ ! -e "$application_scripts" && ! -L "$application_scripts" ]]; then
        wattson_cleanup_add_dir "$application_scripts"
    fi
}

wattson_stop_executable() {
    wattson_run_timeout 15 /usr/bin/python3 "$_WATTSON_CLEANUP_LIB/run_owned.py" --stop-executable "$1"
}

_wattson_cleanup() {
    local status=$?
    trap - EXIT
    trap '' HUP INT TERM
    _WATTSON_RUNNER_STARTING=0
    _WATTSON_PENDING_SIGNAL=0
    set +e
    if [[ -n "${_WATTSON_RUNNER_PID:-}" ]]; then
        kill -TERM "$_WATTSON_RUNNER_PID" 2>/dev/null
        # Wait for the runner's bounded tool or lifecycle cleanup grace period.
        wait "$_WATTSON_RUNNER_PID" 2>/dev/null
        _WATTSON_RUNNER_PID=""
    fi
    local app mountpoint directory failed_mount skip executable defaults_suite registered_app
    local failed_mounts=()
    for executable in "${_WATTSON_CLEANUP_EXECUTABLES[@]+"${_WATTSON_CLEANUP_EXECUTABLES[@]}"}"; do
        if ! wattson_stop_executable "$executable"; then
            [[ "$status" != 0 ]] || status=1
        fi
    done
    for app in "${_WATTSON_CLEANUP_APPS[@]+"${_WATTSON_CLEANUP_APPS[@]}"}"; do
        if ! wattson_unregister_app "$app"; then
            [[ "$status" != 0 ]] || status=1
        fi
    done
    # Expansion can fail before a script learns the nested payload's app path.
    # Search only directories explicitly owned by this invocation.
    for directory in "${_WATTSON_CLEANUP_DIRS[@]+"${_WATTSON_CLEANUP_DIRS[@]}"}"; do
        [[ -d "$directory" && ! -L "$directory" ]] || continue
        while IFS= read -r -d '' app; do
            skip=0
            for registered_app in "${_WATTSON_CLEANUP_APPS[@]+"${_WATTSON_CLEANUP_APPS[@]}"}"; do
                [[ "$app" != "$registered_app" ]] || skip=1
            done
            [[ "$skip" == 0 ]] || continue
            if ! wattson_unregister_app "$app"; then
                [[ "$status" != 0 ]] || status=1
            fi
            _WATTSON_CLEANUP_APPS+=("$app")
        done < <(/usr/bin/find "$directory" -type d -name '*.app' -prune -print0)
    done
    for mountpoint in "${_WATTSON_CLEANUP_MOUNTS[@]+"${_WATTSON_CLEANUP_MOUNTS[@]}"}"; do
        if ! wattson_detach "$mountpoint"; then
            failed_mounts+=("$mountpoint")
            [[ "$status" != 0 ]] || status=1
        fi
    done
    for defaults_suite in "${_WATTSON_CLEANUP_DEFAULTS[@]+"${_WATTSON_CLEANUP_DEFAULTS[@]}"}"; do
        local defaults_status=0
        wattson_run_timeout 10 /usr/bin/defaults delete "$defaults_suite" >/dev/null 2>&1 || defaults_status=$?
        if [[ "$defaults_status" == 124 || ( "$defaults_status" != 0 && -f "$HOME/Library/Preferences/$defaults_suite.plist" ) ]]; then
            echo "Cleanup could not clear defaults domain: $defaults_suite" >&2
            [[ "$status" != 0 ]] || status=1
        fi
        /bin/rm -f -- "$HOME/Library/Preferences/$defaults_suite.plist" || {
            [[ "$status" != 0 ]] || status=1
        }
    done
    for directory in "${_WATTSON_CLEANUP_DIRS[@]+"${_WATTSON_CLEANUP_DIRS[@]}"}"; do
        skip=0
        for failed_mount in "${failed_mounts[@]+"${failed_mounts[@]}"}"; do
            case "$failed_mount/" in "$directory/"*) skip=1 ;; esac
        done
        [[ "$skip" == 0 ]] || continue
        if _wattson_directory_has_mount "$directory"; then
            echo "Cleanup preserved a directory containing an attached volume: $directory" >&2
            [[ "$status" != 0 ]] || status=1
            continue
        fi
        if ! /bin/rm -rf -- "$directory"; then
            [[ "$status" != 0 ]] || status=1
        fi
    done
    exit "$status"
}

wattson_cleanup_init() {
    _WATTSON_CLEANUP_DIRS=()
    _WATTSON_CLEANUP_APPS=()
    _WATTSON_CLEANUP_MOUNTS=()
    _WATTSON_CLEANUP_EXECUTABLES=()
    _WATTSON_CLEANUP_DEFAULTS=()
    _WATTSON_RUNNER_PID=""
    _WATTSON_RUNNER_STARTING=0
    _WATTSON_PENDING_SIGNAL=0
    trap _wattson_cleanup EXIT
    trap '_wattson_signal 129' HUP
    trap '_wattson_signal 130' INT
    trap '_wattson_signal 143' TERM
}
