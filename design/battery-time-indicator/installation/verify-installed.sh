#!/bin/bash
# Read-only baseline/verification of the local 5.0.2 PKG; never install or launch GUI.
set -euo pipefail
unset PYTHONOPTIMIZE
export PYTHONDONTWRITEBYTECODE=1 LC_ALL=C
evidence="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$evidence/../../.." && pwd)"
usage() {
    echo 'usage: verify-installed.sh before ABS_PKG SOURCE_SHA ABS_BEFORE_JSON' >&2
    echo '       verify-installed.sh verify ABS_PKG SOURCE_SHA ABS_BEFORE_JSON ABS_NEW_RESULTS_DIR' >&2
    exit 64
}
[[ "$#" -ge 4 && "$EUID" != 0 ]] || usage
mode="$1"; pkg="$2"; source_commit="$3"; before="$4"
[[ "$pkg" == /* && "$before" == "$evidence/"* ]] || usage
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
if [[ "$mode" == before && "$#" == 4 ]]; then
    [[ ! -e "$before" && ! -L "$before" ]] || exit 65
    wattson_run_timeout 30 /usr/bin/python3 "$evidence/installation_state.py" before "$pkg" "$source_commit" "$before"
elif [[ "$mode" == verify && "$#" == 5 ]]; then
    results="$5"
    [[ "$results" == "$evidence/"* && ! -e "$results" && ! -L "$results" ]] || exit 65
    wattson_run_timeout 30 /usr/bin/python3 "$evidence/installation_state.py" preflight "$pkg" "$source_commit" "$before"
    mkdir "$results"
    status=0
    wattson_run_script "$evidence/verify-payload.sh" "$pkg" "$source_commit" "$before" "$results" \
        > "$results/payload.log" 2> "$results/payload.err" || status=$?
    printf '%s\n' "$status" > "$results/payload-and-cleanup-exit-code.txt"
    [[ "$status" == 0 ]] || exit "$status"
    wattson_run_timeout 90 /usr/bin/python3 "$evidence/installation_state.py" finalize \
        "$results/pending-cleanup.json" "$results/local-install-verified.json" \
        > "$results/finalize.log" 2> "$results/finalize.err"
    cat "$results/finalize.log"
else
    usage
fi
