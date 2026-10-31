#!/bin/bash
# Post-release transport-only retry; no change to frozen validation guards.
set -euo pipefail
umask 077
if [[ "$#" != 2 || ! "$1" =~ ^[1-9][0-9]+$ || ! "$2" =~ ^[0-9a-f]{40}$ ]]; then
    echo 'usage: artifact-public-curl-retry.sh CANDIDATE-RUN-ID SOURCE-SHA' >&2
    exit 2
fi
export WATTSON_RELEASE_CANDIDATE_RUN_ID="$1" WATTSON_RELEASE_SOURCE_SHA="$2"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
evidence="$repo/design/release-v5.0.3/publication"
final="$repo/dist/public-v5.0.3-verify"
proof="$evidence/artifact-public-provenance.json"
[[ ! -e "$final" && ! -L "$final" && ! -e "$proof" && ! -L "$proof" && ! -L "$repo/dist" ]] || exit 1
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$repo/.build/public-v5.0.3.noindex" "$repo/dist"
scratch="$(mktemp -d "$repo/.build/public-v5.0.3.noindex/curl-retry.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
record="$(mktemp -d "$evidence/artifact-public-curl-retry-review.XXXXXX")"
mkdir "$scratch/tmp"
export TMPDIR="$scratch/tmp" PYTHONDONTWRITEBYTECODE=1
unset PYTHONOPTIMIZE
printf '%s\n' "$scratch" > "$record/workspace.txt"
printf '%s\n' "$scratch" > "$evidence/artifact-public-workspace.txt"
echo "Curl retry evidence: $record"
wattson_run_timeout 880 /usr/bin/python3 "$evidence/artifact-public-curl-retry.py" verify "$scratch" "$record"
/bin/mv "$scratch/assets" "$final"
/bin/mv "$scratch/provenance.json" "$proof"
echo "Verified public assets retained: $final"
