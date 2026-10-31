#!/bin/bash
# Authorized canonical install only; input is a public PKG digest, never a password.
set -euo pipefail
umask 077
unset PYTHONOPTIMIZE
export PYTHONDONTWRITEBYTECODE=1
EVIDENCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$EVIDENCE/../../.." && pwd)"
[[ $# == 2 && "$1" =~ ^[0-9a-f]{64}$ && "$2" == "$EVIDENCE/"* && "$EUID" != 0 ]] || {
    echo 'usage: install-authorized-public.sh EXPECTED_PUBLIC_PKG_SHA256 ABS_NEW_RESULTS_DIRECTORY' >&2
    exit 64
}
RESULTS="$2"
[[ "$(dirname "$RESULTS")" == "$EVIDENCE" && ! -e "$RESULTS" && ! -L "$RESULTS" && -t 0 ]] || exit 65
source "$REPO/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$REPO/.build/public-install-v5.0.3.noindex"
SCRATCH="$(mktemp -d "$REPO/.build/public-install-v5.0.3.noindex/auth.XXXXXX")"
wattson_cleanup_add_dir "$SCRATCH"
mkdir "$RESULTS"
printf '%s\n' "$SCRATCH" > "$RESULTS/auth-workspace.txt"
# Keep the controlling terminal for echo-disabled getpass. The manager owns
# its sudo child; the privileged shared runner owns the installer process group.
_WATTSON_RUNNER_STARTING=1
/usr/bin/python3 "$EVIDENCE/install-authorized-public.py" "$1" "$SCRATCH" "$RESULTS" < /dev/tty &
_WATTSON_RUNNER_PID=$!
_wattson_runner_registered
STATUS=0
wait "$_WATTSON_RUNNER_PID" || STATUS=$?
_WATTSON_RUNNER_PID=''
printf '%s\n' "$STATUS" > "$RESULTS/native-installer-exit-code.txt"
exit "$STATUS"
