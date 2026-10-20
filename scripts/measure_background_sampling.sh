#!/bin/bash
# Read-only host measurement. No app bundle, preference suite or helper writes.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$#" != 1 ]]; then
    echo 'usage: measure_background_sampling.sh NEW_OUTPUT_DIRECTORY (frozen baseline d6b40247)' >&2
    exit 64
fi
RESULTS="$1"
if [[ -z "$RESULTS" || -e "$RESULTS" || -L "$RESULTS" ]]; then
    echo 'Output directory must be new; existing measurement evidence is never overwritten.' >&2
    exit 64
fi
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
# Coordination files are owned by this invocation, including failed waits and
# catchable interruption. The shared handler owns every child and scratch path.
return_status() { return "$1"; }
finish() {
    local status=$?
    trap - EXIT
    trap '' HUP INT TERM
    set +e
    /bin/rm -f "$RESULTS/ready" "$RESULTS/go" || status=1
    return_status "$status"
    _wattson_cleanup
}
trap finish EXIT
mkdir -p "$ROOT_DIR/.build/background-sampling.noindex" "$RESULTS"
SCRATCH="$(mktemp -d "$ROOT_DIR/.build/background-sampling.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$SCRATCH"
SOURCES=(Core/PowerSnapshot.swift Core/BatterySampler.swift Core/BatteryRuntimeEstimate.swift Core/SystemBatteryHealth.swift Core/HelperClient.swift Core/RawPowerObservation.swift Core/PowerObservationTrace.swift Core/PowerObservationWireV5.swift Core/HelperClientPowerObservationV5.swift Core/AppleSmartBatteryPowerObservationReader.swift Core/PowerObservationFusion.swift Core/PowerObservationShadow.swift Core/PowerObservationRuntimeController.swift Core/TopProcesses.swift Core/ProcessTermination.swift)
mkdir -p "$SCRATCH/sources" "$SCRATCH/module-cache"
for SOURCE in "${SOURCES[@]}"; do
    /usr/bin/git -C "$ROOT_DIR" show "d6b40247cd50c05af4ec9a99956c8ff1937c4894:$SOURCE" > "$SCRATCH/sources/$(basename "$SOURCE")"
done
cp "$ROOT_DIR/tests/performance/sampling/main.swift" "$SCRATCH/sources/main.swift"
wattson_run_timeout 120 /usr/bin/xcrun swiftc -O -whole-module-optimization \
    -module-cache-path "$SCRATCH/module-cache" -swift-version 5 \
    -target arm64-apple-macos12.0 "$SCRATCH"/sources/*.swift \
    -framework IOKit -o "$SCRATCH/SamplingProbe" > "$RESULTS/build.log" 2>&1
wattson_cleanup_add_executable "$SCRATCH/SamplingProbe"
wattson_run_timeout 30 "$SCRATCH/SamplingProbe" --warmup > "$RESULTS/warmup.jsonl"
/usr/bin/shasum -a 256 "$SCRATCH"/sources/*.swift "$SCRATCH/SamplingProbe" > "$RESULTS/compiled-inputs.sha256"
/usr/bin/touch "$RESULTS/ready"
# Let other performance probes stop compiling before the quiet host window.
wattson_run_timeout 180 /usr/bin/python3 -c '
import pathlib, sys, time
output = pathlib.Path(sys.argv[1])
deadline = time.monotonic() + 150
while not (output / "go").exists():
    if time.monotonic() >= deadline:
        raise SystemExit("Quiet-window signal did not arrive")
    time.sleep(.2)
' "$RESULTS"
/bin/rm "$RESULTS/ready" "$RESULTS/go"
wattson_run_timeout 120 /usr/bin/python3 "$ROOT_DIR/tests/performance/sampling/measure.py" \
    "$ROOT_DIR" "$SCRATCH/SamplingProbe" "$RESULTS"
