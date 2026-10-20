#!/bin/bash
set -euo pipefail
SHARE='/Volumes/My Shared Files/task'
# This bootstrap only uses read-only lifecycle helpers; measured tools and code
# are separately hashed and copied into guest-local storage before execution.
source '/Volumes/My Shared Files/repo/scripts/lib/local_cleanup.sh'
wattson_cleanup_init
GUEST_PARENT="$HOME/Project/.wattson-ui-vm.noindex"
mkdir -p "$GUEST_PARENT"
RUN_DIR="$(mktemp -d "$GUEST_PARENT/run.XXXXXX")"
wattson_cleanup_add_dir "$RUN_DIR"
/usr/bin/python3 "$SHARE/ui_vm.py" before > "$SHARE/results/guest-before.json"
/usr/bin/sw_vers > "$SHARE/results/system.txt"
xcrun swift --version >> "$SHARE/results/system.txt"
xcrun --show-sdk-version >> "$SHARE/results/system.txt"
/usr/bin/python3 - "$SHARE" "$RUN_DIR" <<'PY'
import hashlib,json,os,pathlib,shutil,sys,tarfile
share,run=map(pathlib.Path,sys.argv[1:]); manifest=json.loads((share/'manifest.json').read_text())
(share/'results/python-guest-validation.json').write_text(json.dumps({'PYTHONOPTIMIZE':os.environ.get('PYTHONOPTIMIZE'),'optimize':sys.flags.optimize}))
for archive,digest in manifest['archives'].items():
    target=run/archive; shutil.copyfile(share/archive,target)
    if hashlib.sha256(target.read_bytes()).hexdigest()!=digest:
        raise RuntimeError('Archive SHA-256 mismatch: '+archive)
    label=archive.removesuffix('.tar.gz'); destination=run/label; destination.mkdir()
    with tarfile.open(target) as bundle: bundle.extractall(destination)
for label in manifest['sources']:
    shutil.copytree(run/'tools',run/label,dirs_exist_ok=True)
if 'diagnosticPatchSHA256' in manifest:
    patch=(share/'diagnostic.patch').read_bytes()
    if hashlib.sha256(patch).hexdigest()!=manifest['diagnosticPatchSHA256']:
        raise RuntimeError('Diagnostic patch SHA-256 mismatch')
    (run/'diagnostic.patch').write_bytes(patch)
(run/'manifest.json').write_text(json.dumps(manifest))
PY
DIAGNOSTIC=0
if [[ -f "$RUN_DIR/diagnostic.patch" ]]; then
    DIAGNOSTIC=1
    cd "$RUN_DIR/baseline"
    wattson_run_timeout 20 /usr/bin/patch --batch --forward -p1 --input "$RUN_DIR/diagnostic.patch" \
        > "$SHARE/results/diagnostic-patch.log" 2>&1
    /usr/bin/grep -q 'UIOpenAttribution' "$RUN_DIR/baseline/Popover/PopoverController.swift"
    /usr/bin/grep -q '"diagnostic_only": true' "$RUN_DIR/baseline/tests/performance/ui-latency.swift"
    /usr/bin/grep -q '"open_attribution"' "$RUN_DIR/baseline/tests/performance/ui-latency.swift"
    /bin/cp "$RUN_DIR/diagnostic.patch" "$SHARE/results/diagnostic.patch"
fi
# Keep all runs on the same clone and display. A candidate selects ABBA order.
ORDER=(baseline)
if /usr/bin/python3 -c 'import json,sys;sys.exit(0 if json.load(open(sys.argv[1]))["configuration"]["repeatBaseline"]==2 else 1)' "$RUN_DIR/manifest.json"; then
    ORDER=(baseline baseline)
fi
[[ -d "$RUN_DIR/candidate" ]] && ORDER=(baseline candidate candidate baseline)
# Validate the actual NSApp milestones with one sample before collecting a
# long baseline; this separate result is excluded from the measured block.
read -r COLD_COUNT WARM_COUNT THEME_COUNT SUBMISSION COLOR_SCHEME <<< "$(/usr/bin/python3 -c 'import json,sys;c=json.load(open(sys.argv[1]))["configuration"];print(c["cold"],c["warm"],c["theme"],c["submission"],c["colorScheme"])' "$RUN_DIR/manifest.json")"
APPEARANCE_CONTROLS=0
SCHEMES=("$COLOR_SCHEME")
if /usr/bin/python3 -c 'import json,sys;sys.exit(0 if json.load(open(sys.argv[1]))["appearanceControls"] else 1)' "$RUN_DIR/manifest.json"; then
    APPEARANCE_CONTROLS=1
    SCHEMES=(system light)
    ORDER=(baseline candidate)
fi
if [[ "$APPEARANCE_CONTROLS" != 1 ]]; then
SMOKE_COLD=1; SMOKE_WARM=1; SMOKE_THEME=1
SINGLE_DIAGNOSTIC=0
SMOKE_RESULT="$SHARE/results/smoke-baseline.jsonl"
if [[ "$DIAGNOSTIC" == 1 ]]; then SMOKE_COLD=0; SMOKE_THEME=0; fi
if /usr/bin/python3 -c 'import json,sys;sys.exit(0 if json.load(open(sys.argv[1]))["singleDiagnosticPass"] else 1)' "$RUN_DIR/manifest.json"; then
    SINGLE_DIAGNOSTIC=1
    SMOKE_WARM="$WARM_COUNT"
    SMOKE_RESULT="$SHARE/results/single-diagnostic.jsonl"
fi
printf 'UI_MEASUREMENT_SMOKE_BEGIN\n'
SMOKE_REVISION="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sources"]["baseline"]["revision"])' "$RUN_DIR/manifest.json")"
WATTSON_PERF_SOURCE_REVISION="$SMOKE_REVISION" \
    WATTSON_PERF_COLD_COUNT="$SMOKE_COLD" WATTSON_PERF_WARM_COUNT="$SMOKE_WARM" \
    WATTSON_PERF_THEME_COUNT="$SMOKE_THEME" WATTSON_PERF_SUBMISSION="$SUBMISSION" WATTSON_PERF_COLOR_SCHEME="$COLOR_SCHEME" \
    wattson_run_script "$RUN_DIR/baseline/scripts/measure_ui_latency.sh" --run-gui \
    "$SMOKE_RESULT" > "$SHARE/results/smoke-baseline.log" 2>&1
/usr/bin/python3 "$SHARE/ui_vm.py" verify-result "$SMOKE_RESULT" "$DIAGNOSTIC" "$SINGLE_DIAGNOSTIC" \
    > "$SHARE/results/smoke-verification.json"
printf 'UI_MEASUREMENT_SMOKE_PASSED\n'
[[ "$SINGLE_DIAGNOSTIC" != 1 ]] || exit 0
if /usr/bin/python3 -c 'import json,sys;sys.exit(0 if json.load(open(sys.argv[1]))["smokeOnly"] else 1)' "$RUN_DIR/manifest.json"; then
    exit 0
fi
fi
if [[ "$DIAGNOSTIC" == 1 ]]; then COLD_COUNT=0; WARM_COUNT=20; THEME_COUNT=0; fi
BLOCK=0
for COLOR_SCHEME in "${SCHEMES[@]}"; do
for LABEL in "${ORDER[@]}"; do
    BLOCK=$((BLOCK + 1))
    SUFFIX=''
    [[ "$APPEARANCE_CONTROLS" != 1 ]] || SUFFIX="-$COLOR_SCHEME"
    SOURCE_REVISION="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sources"][sys.argv[2]]["revision"])' "$RUN_DIR/manifest.json" "$LABEL")"
    printf 'UI_MEASUREMENT_BLOCK_BEGIN %s %s %s\n' "$BLOCK" "$LABEL" "$SOURCE_REVISION"
    WATTSON_PERF_SOURCE_REVISION="$SOURCE_REVISION" \
        WATTSON_PERF_COLD_COUNT="$COLD_COUNT" WATTSON_PERF_WARM_COUNT="$WARM_COUNT" \
        WATTSON_PERF_THEME_COUNT="$THEME_COUNT" WATTSON_PERF_SUBMISSION="$SUBMISSION" WATTSON_PERF_COLOR_SCHEME="$COLOR_SCHEME" \
        wattson_run_script "$RUN_DIR/$LABEL/scripts/measure_ui_latency.sh" --run-gui \
        "$SHARE/results/block-$BLOCK-$LABEL$SUFFIX.jsonl" \
        > "$SHARE/results/block-$BLOCK-$LABEL$SUFFIX.log" 2>&1
    /usr/bin/python3 "$SHARE/ui_vm.py" verify-result "$SHARE/results/block-$BLOCK-$LABEL$SUFFIX.jsonl" "$DIAGNOSTIC" \
        > "$SHARE/results/block-$BLOCK-$LABEL$SUFFIX-verification.json"
    printf 'UI_MEASUREMENT_BLOCK_PASSED %s %s\n' "$BLOCK" "$LABEL"
done
done
if [[ "$APPEARANCE_CONTROLS" == 1 ]]; then
    printf 'UI_INTERACTION_REGRESSION_BEGIN\n'
    wattson_run_script "$RUN_DIR/candidate/scripts/verify_interaction.sh" > "$SHARE/results/candidate-interaction.log" 2>&1
    printf '{"allPassed":true,"source":"candidate","entrypoint":"scripts/verify_interaction.sh"}\n' > "$SHARE/results/interaction-verification.json"
    printf 'UI_INTERACTION_REGRESSION_PASSED\n'
fi
printf 'UI_MEASUREMENT_ALL_BLOCKS_PASSED\n'
