#!/bin/bash
# Production-renderer captures run only in a disposable ARM GUI VM.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_ONLY=0
GRADIENT_COMPARISON=0
COMPACT_ONLY=0
if [[ "${1:-}" == --module-only ]]; then
    MODULE_ONLY=1
    shift
elif [[ "${1:-}" == --gradient-comparison ]]; then
    GRADIENT_COMPARISON=1
    shift
elif [[ "${1:-}" == --compact-only ]]; then
    COMPACT_ONLY=1
    shift
fi
if [[ "$#" != 1 || "${WATTSON_RUN_GUI_TESTS:-}" != 1 || "$(/usr/sbin/sysctl -n hw.model)" != VirtualMac* ]]; then
    echo 'usage (disposable macOS VM only): WATTSON_RUN_GUI_TESTS=1 verify_top_processes.sh [--module-only|--gradient-comparison|--compact-only] OUTPUT_DIRECTORY' >&2
    exit 64
fi
RESULTS="$1"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$RESULTS" "$ROOT_DIR/.build/top-processes-capture.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/top-processes-capture.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
APP_DIR="$BUILD_DIR/TopProcessesProbe.app"
TEST_BUNDLE_ID="com.leoarrow.wattson.topprocessesqa.$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
wattson_cleanup_add_app "$APP_DIR"
wattson_cleanup_add_container "$TEST_BUNDLE_ID"
wattson_cleanup_add_executable "$APP_DIR/Contents/MacOS/TopProcessesProbe"
return_status() { return "$1"; }
finish() {
    local status=$?
    trap - EXIT
    trap '' HUP INT TERM
    set +e
    if [[ -n "${_WATTSON_RUNNER_PID:-}" ]]; then
        kill -TERM "$_WATTSON_RUNNER_PID" 2>/dev/null
        wait "$_WATTSON_RUNNER_PID" 2>/dev/null
        _WATTSON_RUNNER_PID=''
    fi
    wattson_stop_executable "$APP_DIR/Contents/MacOS/TopProcessesProbe" || status=1
    wattson_unregister_app "$APP_DIR" || status=1
    /bin/rm -rf -- "$APP_DIR" || status=1
    # NSStatusItem can queue a defaults write after process and registration
    # teardown. Clear both Foundation and the preferences daemon, then remove
    # any empty plist materialized by the CLI's missing-domain check.
    wattson_run_timeout 15 /usr/bin/osascript -l JavaScript "$BUILD_DIR/clear-defaults.js" "$TEST_BUNDLE_ID" > "$RESULTS/defaults-synchronized.json" 2> "$RESULTS/defaults-cleanup.err" || status=1
    local defaults_status=0
    wattson_run_timeout 10 /usr/bin/defaults delete "$TEST_BUNDLE_ID" > "$RESULTS/defaults-delete.log" 2>&1 || defaults_status=$?
    [[ "$defaults_status" == 0 || "$defaults_status" == 1 ]] || status=1
    wattson_run_timeout 10 /usr/bin/python3 "$BUILD_DIR/finalize-defaults.py" "$TEST_BUNDLE_ID" > "$RESULTS/defaults-finalized.json" 2>> "$RESULTS/defaults-cleanup.err" || status=1
    return_status "$status"
    _wattson_cleanup
}
trap finish EXIT
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cat > "$BUILD_DIR/clear-defaults.js" <<'JXA'
ObjC.import("Foundation");
function run(args) {
  if (args.length !== 1 || !/^com\.leoarrow\.wattson\.topprocessesqa\.[a-f0-9-]{36}$/.test(args[0])) throw new Error("Expected owned capture UUID domain");
  const domain = args[0], defaults = $.NSUserDefaults.alloc.initWithSuiteName(domain);
  const path = $.NSHomeDirectory().js + "/Library/Preferences/" + domain + ".plist";
  const manager = $.NSFileManager.defaultManager;
  let stable = 0;
  for (let attempt = 0; attempt < 40 && stable < 10; attempt++) {
    defaults.removePersistentDomainForName(domain);
    if (!defaults.synchronize) throw new Error("Owned domain synchronization failed");
    if (manager.fileExistsAtPath(path) && !manager.removeItemAtPathError(path, null)) throw new Error("Owned plist removal failed");
    $.NSThread.sleepForTimeInterval(0.2);
    stable = manager.fileExistsAtPath(path) ? 0 : stable + 1;
  }
  if (stable < 10) throw new Error("Owned defaults did not settle");
  return JSON.stringify({ownedDomain: domain, synchronized: true, stableSeconds: 2});
}
JXA
cat > "$BUILD_DIR/finalize-defaults.py" <<'PYTHON'
import pathlib, re, sys, time
domain = sys.argv[1]
assert re.fullmatch(r"com\.leoarrow\.wattson\.topprocessesqa\.[a-f0-9-]{36}", domain)
path = pathlib.Path.home() / "Library/Preferences" / (domain + ".plist")
deadline = time.monotonic() + 8
stable = time.monotonic()
while time.monotonic() < deadline:
    if path.exists():
        assert path.is_file() and not path.is_symlink()
        path.unlink()
        stable = time.monotonic()
    if time.monotonic() - stable >= 3:
        print('{"latePlistRemoved":true,"stableSeconds":3}')
        break
    time.sleep(0.1)
else:
    raise SystemExit("Owned defaults reappeared after synchronization")
PYTHON
cp "$ROOT_DIR"/design/icon/in-app-logo/*.png "$APP_DIR/Contents/Resources/"
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>TopProcessesProbe</string>
<key>CFBundleIdentifier</key><string>${TEST_BUNDLE_ID}</string>
<key>CFBundleExecutable</key><string>TopProcessesProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$(cat "$ROOT_DIR/VERSION")</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
wattson_run xcrun clang -mmacosx-version-min=12.0 -Wno-deprecated-declarations \
    -c "$ROOT_DIR/tests/visual/capture_glass_shadow.c" -o "$BUILD_DIR/capture.o" > "$RESULTS/build.log" 2>&1
wattson_run xcrun swiftc "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift \
    "$ROOT_DIR"/Popover/*.swift "$ROOT_DIR/tests/visual/capture_top_processes.swift" \
    "$BUILD_DIR/capture.o" -D DEBUG -swift-version 5 -warnings-as-errors \
    -import-objc-header "$ROOT_DIR/tests/visual/capture_glass_shadow.h" \
    -framework AppKit -framework CoreGraphics -framework IOKit \
    -o "$APP_DIR/Contents/MacOS/TopProcessesProbe" >> "$RESULTS/build.log" 2>&1
wattson_run codesign --force --sign - "$APP_DIR" >> "$RESULTS/build.log" 2>&1
printf 'bundleID=%s\nbundlePath=%s\n' "$TEST_BUNDLE_ID" "$APP_DIR" > "$RESULTS/capture-provenance.txt"
printf 'moduleOnly=%s\n' "$MODULE_ONLY" >> "$RESULTS/capture-provenance.txt"
printf 'gradientComparison=%s\n' "$GRADIENT_COMPARISON" >> "$RESULTS/capture-provenance.txt"
printf 'compactOnly=%s\n' "$COMPACT_ONLY" >> "$RESULTS/capture-provenance.txt"
printf 'highContrast=%s\n' "${WATTSON_FORCE_INCREASE_CONTRAST:-0}" >> "$RESULTS/capture-provenance.txt"
/usr/bin/shasum -a 256 "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/Popover/*.swift \
    "$ROOT_DIR"/MenuBar/*.swift "$ROOT_DIR/tests/visual/capture_top_processes.swift" \
    "$APP_DIR/Contents/MacOS/TopProcessesProbe" > "$RESULTS/capture-inputs.sha256"
PROBE_ARGUMENTS=("$RESULTS")
PROBE_TIMEOUT=240
if [[ "$MODULE_ONLY" == 1 ]]; then
    PROBE_ARGUMENTS=(--module-only "$RESULTS")
    PROBE_TIMEOUT=60
elif [[ "$GRADIENT_COMPARISON" == 1 ]]; then
    PROBE_ARGUMENTS=(--gradient-comparison "$RESULTS")
    PROBE_TIMEOUT=60
elif [[ "$COMPACT_ONLY" == 1 ]]; then
    PROBE_ARGUMENTS=(--compact-only "$RESULTS")
    PROBE_TIMEOUT=60
fi
wattson_run_timeout "$PROBE_TIMEOUT" /usr/bin/env WATTSON_FORCE_REDUCE_MOTION=1 \
    WATTSON_FORCE_REDUCE_TRANSPARENCY=0 WATTSON_FORCE_INCREASE_CONTRAST="${WATTSON_FORCE_INCREASE_CONTRAST:-0}" \
    "$APP_DIR/Contents/MacOS/TopProcessesProbe" "${PROBE_ARGUMENTS[@]}" > "$RESULTS/run.log" 2> "$RESULTS/run.err"
[[ -s "$RESULTS/evidence.json" ]]
