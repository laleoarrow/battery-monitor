#!/bin/bash
# Read-only verification AFTER root installs the exact approved public PKG.
set -euo pipefail
unset PYTHONOPTIMIZE
export PYTHONDONTWRITEBYTECODE=1 LC_ALL=C
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
evidence="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$#" -lt 4 || "$#" -gt 5 ]]; then
    echo 'usage: verify-installed.sh ABS_PUBLIC_PKG APPROVED_SHA256 SOURCE_SHA PUBLIC_PROVENANCE_JSON [BEFORE_JSON]' >&2
    exit 64
fi
pkg="$1"; approved_sha="$2"; source_commit="$3"; provenance="$4"
before="${5:-$evidence/before.json}"
[[ "$pkg" == /* && -f "$pkg" && "$approved_sha" =~ ^[0-9a-f]{64}$ && "$source_commit" =~ ^[0-9a-f]{40}$ ]] || exit 64
[[ "$EUID" != 0 && ! -e "$evidence/local-install-verified.json" ]] || exit 65
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
wattson_run_timeout 30 /usr/bin/python3 "$evidence/verify_details.py" identity "$pkg" "$approved_sha" "$source_commit" "$provenance" "$before"
attempt="$evidence/checks-$(/bin/date -u '+%Y%m%dT%H%M%SZ')-$$"
mkdir "$attempt"
# The inner shell owns and waits for its commands, App and scratch. A successful
# runner return includes that shell's shared EXIT cleanup, not just its checks.
payload_status=0
wattson_run_script "$evidence/verify-payload.sh" "$pkg" "$approved_sha" "$source_commit" "$provenance" "$before" "$attempt" > "$attempt/payload.log" 2> "$attempt/payload.err" || payload_status=$?
printf '%s\n' "$payload_status" > "$attempt/payload-and-cleanup-exit-code.txt"
[[ "$payload_status" == 0 ]] || exit "$payload_status"
wattson_run_timeout 90 /usr/bin/python3 "$evidence/verify_details.py" finalize "$attempt/checks-passed-before-cleanup.json" "$evidence/local-install-verified.json" > "$attempt/finalize.log" 2> "$attempt/finalize.err"
/bin/cat "$attempt/finalize.log"
