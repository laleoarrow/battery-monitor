#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EVIDENCE="$ROOT/design/release-v4.3.22/publication"
source "$ROOT/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT/.build/public-v4.3.22.noindex"
public_workspace="$(/usr/bin/mktemp -d "$ROOT/.build/public-v4.3.22.noindex/download.XXXXXX")"
wattson_cleanup_add_dir "$public_workspace"
mkdir "$public_workspace/tmp"
export TMPDIR="$public_workspace/tmp"
export PYTHONDONTWRITEBYTECODE=1
test ! -e "$ROOT/dist/public-v4.3.22-verify" || { echo 'Refusing to overwrite retained public inputs.' >&2; exit 1; }
printf '%s\n' "$public_workspace" > "$EVIDENCE/artifact-public-workspace-v4.3.22.txt"
wattson_run_timeout 160 /usr/bin/python3 "$EVIDENCE/artifact-inspect-39145124379.py" snapshot "$public_workspace" "$EVIDENCE/artifact-public-before-v4.3.22.json"
wattson_run_timeout 520 /usr/bin/python3 "$EVIDENCE/artifact-public-urllib-v4.3.22.py" "$public_workspace"
mv "$public_workspace/assets" "$ROOT/dist/public-v4.3.22-verify"
echo 'Exact four public installer assets retained; shared owner will remove download scratch.'
