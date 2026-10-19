#!/bin/bash
# Anonymous byte comparison only; no build/install/publication or bundle replay.
set -euo pipefail
umask 077
[[ "$#" == 0 ]] || { echo 'usage: /bin/bash artifact-public-verify.sh' >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EVIDENCE="$ROOT/design/release-v4.3.23/publication"
final="$ROOT/dist/public-v4.3.23-verify"
proof="$EVIDENCE/artifact-public-provenance.json"
[[ ! -e "$final" && ! -L "$final" && ! -e "$proof" && ! -L "$proof" ]] || {
    echo 'Refusing to overwrite retained public inputs or provenance.' >&2; exit 1;
}
[[ ! -L "$ROOT/dist" ]] || { echo 'dist must not be a symlink.' >&2; exit 1; }
source "$ROOT/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT/.build/public-v4.3.23.noindex" "$ROOT/dist"
public_workspace="$(mktemp -d "$ROOT/.build/public-v4.3.23.noindex/download.XXXXXX")"
wattson_cleanup_add_dir "$public_workspace"
mkdir "$public_workspace/tmp"
export TMPDIR="$public_workspace/tmp"
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONOPTIMIZE
printf '%s\n' "$public_workspace" > "$EVIDENCE/artifact-public-workspace.txt"
wattson_run_timeout 520 /usr/bin/python3 "$EVIDENCE/artifact-public-download.py" "$public_workspace"
/bin/mv "$public_workspace/assets" "$final"
/bin/mv "$public_workspace/provenance.json" "$proof"
echo "Verified public assets retained: $final"
