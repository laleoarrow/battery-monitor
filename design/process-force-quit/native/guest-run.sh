#!/bin/bash
set -euo pipefail
share='/Volumes/My Shared Files/review'
source '/Volumes/My Shared Files/repo/scripts/lib/local_cleanup.sh'
wattson_cleanup_init
output=''
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
    if [[ -n "$output" && -d "$output" && ! -e "$share/results/gui" ]]; then
        cp -R "$output" "$share/results/gui" || status=1
    fi
    return_status "$status"
    _wattson_cleanup
}
trap finish EXIT
mkdir -p "$HOME/Project/.process-force-quit.noindex" "$share/results"
run_dir="$(mktemp -d "$HOME/Project/.process-force-quit.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$run_dir"
cp "/Volumes/My Shared Files/snapshot/source.tar.gz" "$run_dir/source.tar.gz"
[[ "$(shasum -a 256 "$run_dir/source.tar.gz" | awk '{print $1}')" == "$(cat "/Volumes/My Shared Files/snapshot/source.sha256")" ]]
mkdir "$run_dir/source"
tar -xzf "$run_dir/source.tar.gz" -C "$run_dir/source"
src="$run_dir/source"
sw_vers > "$share/results/system.txt"
xcrun swift --version >> "$share/results/system.txt"
wattson_run_timeout 60 xcrun swiftc "$src/design/process-force-quit/native/display-probe.swift" -framework AppKit -o "$run_dir/DisplayProbe" > "$share/results/display-build.log" 2>&1
"$run_dir/DisplayProbe" > "$share/results/system-before.json"
app="$run_dir/ProcessForceQuitProbe.app"
identifier="com.leoarrow.wattson.forcequitqa.$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
wattson_cleanup_add_app "$app"
wattson_cleanup_add_container "$identifier"
wattson_cleanup_add_executable "$app/Contents/MacOS/ProcessForceQuitProbe"
wattson_cleanup_add_defaults "$identifier"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$src"/design/icon/in-app-logo/*.png "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleName</key><string>Process Force Quit QA</string><key>CFBundleIdentifier</key><string>$identifier</string><key>CFBundleExecutable</key><string>ProcessForceQuitProbe</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
EOF
wattson_run_timeout 90 xcrun swiftc -parse-as-library -swift-version 5 -warnings-as-errors "$src/Popover/ProcessTerminationPresenter.swift" "$src/design/process-force-quit/native/alert-probe.swift" -framework AppKit -o "$app/Contents/MacOS/ProcessForceQuitProbe" > "$share/results/alert-probe-build.log" 2>&1
wattson_run_timeout 30 codesign --force --sign - --entitlements "$src/BatteryPowerApp.entitlements" "$app" >> "$share/results/alert-probe-build.log" 2>&1
wattson_run_timeout 15 "$app/Contents/MacOS/ProcessForceQuitProbe" > "$share/results/alert-probe.log" 2> "$share/results/alert-probe.err"
printf 'TINY_NATIVE_CONFIRMATION_PASSED\n'
wattson_run_timeout 60 xcrun clang -mmacosx-version-min=12.0 -Wno-deprecated-declarations -c "$src/tests/visual/capture_glass_shadow.c" -o "$run_dir/capture.o" > "$share/results/gui-build.log" 2>&1
wattson_run_timeout 240 xcrun swiftc "$src"/Core/*.swift "$src"/MenuBar/*.swift "$src"/Popover/*.swift "$src/tests/visual/capture_process_force_quit.swift" "$run_dir/capture.o" -D DEBUG -swift-version 5 -warnings-as-errors -import-objc-header "$src/tests/visual/capture_glass_shadow.h" -framework AppKit -framework CoreGraphics -framework IOKit -o "$app/Contents/MacOS/ProcessForceQuitProbe" >> "$share/results/gui-build.log" 2>&1
wattson_run_timeout 30 codesign --force --sign - --entitlements "$src/BatteryPowerApp.entitlements" "$app" >> "$share/results/gui-build.log" 2>&1
printf 'bundleID=%s\nsandboxed=true\n' "$identifier" > "$share/results/provenance.txt"
shasum -a 256 "$src"/Core/*.swift "$src"/MenuBar/*.swift "$src"/Popover/*.swift "$src/tests/visual/capture_process_force_quit.swift" "$app/Contents/MacOS/ProcessForceQuitProbe" > "$share/results/gui-inputs.sha256"
output="$HOME/Library/Containers/$identifier/Data/Library/Application Support/ForceQuitEvidence"
wattson_run_timeout 240 /usr/bin/env WATTSON_FORCE_REDUCE_MOTION=1 WATTSON_FORCE_REDUCE_TRANSPARENCY=0 WATTSON_FORCE_INCREASE_CONTRAST=0 "$app/Contents/MacOS/ProcessForceQuitProbe" "$output" > "$share/results/gui-run.log" 2> "$share/results/gui-run.err"
cp -R "$output" "$share/results/gui"
[[ -s "$share/results/gui/evidence.json" ]]
printf 'SANDBOXED_NATIVE_UI_PASSED\n'
cd "$src"
helper="$run_dir/wattson-helper"
wattson_run_timeout 150 xcrun swiftc -swift-version 5 -emit-library -static -emit-module -module-name WattsonHelperV5Support "$src"/HelperV5/*.swift -emit-module-path "$run_dir/WattsonHelperV5Support.swiftmodule" -o "$run_dir/libWattsonHelperV5Support.a" > "$share/results/helper-build.log" 2>&1
wattson_run_timeout 150 xcrun swiftc -swift-version 5 -parse-as-library -I "$run_dir" -L "$run_dir" -lWattsonHelperV5Support "$src/Helper/wattson-helper.swift" -framework IOKit -o "$helper" >> "$share/results/helper-build.log" 2>&1
wattson_run_timeout 90 xcrun swiftc -swift-version 5 -parse-as-library -I "$run_dir" -L "$run_dir" -lWattsonHelperV5Support "$src/design/process-force-quit/native/root-worker-probe.swift" -framework IOKit -o "$run_dir/RootWorkerProbe" > "$share/results/worker-probe-build.log" 2>&1
shasum -a 256 "$src/Helper/wattson-helper.swift" "$src"/HelperV5/*.swift "$src/design/process-force-quit/native/root-worker-probe.swift" "$helper" "$run_dir/RootWorkerProbe" > "$share/results/worker-inputs.sha256"
wattson_run_timeout 30 "$run_dir/RootWorkerProbe" "$helper" > "$share/results/root-worker.json" 2> "$share/results/root-worker.err"
printf 'OWNED_CHILD_ROOT_WORKER_PASSED\n'
"$run_dir/DisplayProbe" > "$share/results/system-after.json"
python3 - "$share/results" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); before=json.loads((p/'system-before.json').read_text()); after=json.loads((p/'system-after.json').read_text())
assert before==after,(before,after)
(p/'accessibility-preserved.json').write_text(json.dumps({'unchanged':True,'before':before,'after':after,'systemAccessibilityWritten':False},indent=2)+'\n')
PY
printf 'PROCESS_FORCE_QUIT_NATIVE_AND_WORKER_PASSED\n'
