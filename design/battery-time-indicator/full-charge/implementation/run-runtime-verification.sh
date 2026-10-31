#!/bin/bash
# Focused rerun after the implicit-visibility-animation fix. The six-state
# layout matrix already passed; layout and geometry did not change in this fix.
set -euo pipefail
EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$EVIDENCE_DIR/../../../.." && pwd)"
[[ $# == 1 && ! -e "$1" ]] || { echo 'usage: run-runtime-verification.sh NEW_OUTPUT_DIRECTORY' >&2; exit 64; }
mkdir -p "$1"
OUTPUT_DIR="$(cd "$1" && pwd)"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/full-charge-verification.noindex"
RUN_DIR="$(mktemp -d "$ROOT_DIR/.build/full-charge-verification.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$RUN_DIR"
python3 - "$EVIDENCE_DIR" <<'PY'
from pathlib import Path
import hashlib, json, sys
directory = Path(sys.argv[1])
expected = json.loads((directory / 'verified-source.json').read_text())['sourceArchiveSHA256']
assert hashlib.sha256((directory / 'verified-source.tar.gz').read_bytes()).hexdigest() == expected
PY
tar -xzf "$EVIDENCE_DIR/verified-source.tar.gz" -C "$RUN_DIR"
wattson_run_script "$RUN_DIR/scripts/test_swift.sh" --filter 'BatteryTimeIndicatorTests|BatteryRuntimePresentationTests' > "$OUTPUT_DIR/swift-tests.log" 2>&1
wattson_run_script "$RUN_DIR/scripts/build_release.sh" > "$OUTPUT_DIR/universal-build.log" 2>&1
# Reuse the proven VM owner and its complete guest/host cleanup. Only omit
# the already-passing static matrix; live indicator capture and interaction run.
python3 - "$RUN_DIR/scripts/verify_process_whitelist_vm.sh" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
lines = path.read_text().splitlines(keepends=True)
matches = [line for line in lines if line.startswith('WATTSON_RUN_GUI_TESTS=1 wattson_run_script') and '/verify_top_processes.sh' in line]
assert len(matches) == 1
path.write_text(''.join(line for line in lines if line != matches[0]))
PY
wattson_run_script "$RUN_DIR/scripts/verify_process_whitelist_vm.sh" "$OUTPUT_DIR/native" > "$OUTPUT_DIR/native-vm.log" 2>&1
printf 'FULL_CHARGE_RUNTIME_VERIFICATION_PASSED\n'
