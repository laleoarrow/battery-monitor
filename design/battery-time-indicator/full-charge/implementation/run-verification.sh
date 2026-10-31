#!/bin/bash
# Verify the retained immutable full-charge source without concurrent edits.
set -euo pipefail
EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$EVIDENCE_DIR/../../../.." && pwd)"
[[ $# == 1 && ! -e "$1" ]] || { echo 'usage: run-verification.sh NEW_OUTPUT_DIRECTORY' >&2; exit 64; }
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
SWIFT_STATUS=0
wattson_run_script "$RUN_DIR/scripts/test_swift.sh" > "$OUTPUT_DIR/swift-tests.log" 2>&1 || SWIFT_STATUS=$?
if [[ "$SWIFT_STATUS" != 0 ]]; then
    # Do not hide regressions. The unchanged SDK-dependent slider assertion
    # must fail identically on the retained pre-change baseline before the
    # independent native full-charge acceptance is allowed to continue.
    python3 - "$EVIDENCE_DIR/baseline-slider.log" "$OUTPUT_DIR/swift-tests.log" <<'PY'
from pathlib import Path
import sys
def failures(path):
    return [line.split(': error: ', 1)[1] for line in Path(path).read_text().splitlines() if ': error: ' in line]
baseline, current = map(failures, sys.argv[1:])
assert len(baseline) == 3 and baseline == current
assert all('testModeSliderRestingSelectionMeetsTrackEdges' in line for line in baseline)
assert 'SWIFT_TEST_DEFAULTS_CLEANUP registered=' in Path(sys.argv[2]).read_text()
print('KNOWN_BASELINE_FAILURE: unchanged slider corner-radius test; full-suite result retained.')
PY
fi
wattson_run_script "$RUN_DIR/scripts/verify_process_whitelist_vm.sh" "$OUTPUT_DIR/native" > "$OUTPUT_DIR/native-vm.log" 2>&1
wattson_run_script "$RUN_DIR/scripts/build_release.sh" > "$OUTPUT_DIR/universal-build.log" 2>&1
printf 'FULL_CHARGE_NATIVE_AND_UNIVERSAL_VERIFICATION_PASSED swift_status=%s\n' "$SWIFT_STATUS"
