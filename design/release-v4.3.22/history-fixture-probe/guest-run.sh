#!/bin/bash
set -euo pipefail
share='/Volumes/My Shared Files/review'
snapshot='/Volumes/My Shared Files/snapshot'
source "$snapshot/local_cleanup.sh"
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
    if [[ -n "$output" && -d "$output" && ! -e "$share/results/probe" ]]; then
        cp -R "$output" "$share/results/probe" || status=1
    fi
    return_status "$status"
    _wattson_cleanup
}
trap finish EXIT
mkdir -p "$HOME/Project/.history-fixture-probe.noindex" "$share/results"
run_dir="$(mktemp -d "$HOME/Project/.history-fixture-probe.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$run_dir"
[[ "$(shasum -a 256 "$snapshot/source.tar.gz" | awk '{print $1}')" == "$(cat "$snapshot/source.sha256")" ]]
[[ "$(shasum -a 256 "$snapshot/probe.swift" | awk '{print $1}')" == "$(cat "$snapshot/probe.sha256")" ]]
mkdir "$run_dir/source"
tar -xzf "$snapshot/source.tar.gz" -C "$run_dir/source"
cp "$snapshot/probe.swift" "$run_dir/probe.swift"
src="$run_dir/source"
python3 "$snapshot/source-manifest.py" verify "$src" "$snapshot/frozen-source-inputs.sha256" "$share/results/source-before.json"
[[ ! -e /Applications/Wattson.app && ! -e /Library/PrivilegedHelperTools/com.leoarrow.wattson.helper && ! -e /var/run/wattson-helper.sock ]]
sw_vers > "$share/results/system.txt"
xcrun swift --version >> "$share/results/system.txt"
launchctl managername > "$share/results/session.txt"
python3 - "$share/results/session.txt" <<'PY'
import pathlib, sys
assert 'Aqua' in pathlib.Path(sys.argv[1]).read_text()
PY
wattson_run_timeout 60 xcrun swiftc "$src/design/process-force-quit/native/display-probe.swift" -framework AppKit -o "$run_dir/DisplayProbe" > "$share/results/display-build.log" 2>&1
wattson_run_timeout 15 "$run_dir/DisplayProbe" > "$share/results/system-before.json"
app="$run_dir/HistoryFixtureProbe.app"
identifier="com.leoarrow.wattson.historyfixtureprobe.$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
wattson_cleanup_add_app "$app"
wattson_cleanup_add_container "$identifier"
wattson_cleanup_add_executable "$app/Contents/MacOS/HistoryFixtureProbe"
wattson_cleanup_add_defaults "$identifier"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$src"/design/icon/in-app-logo/*.png "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleName</key><string>History Fixture Probe</string><key>CFBundleIdentifier</key><string>$identifier</string><key>CFBundleExecutable</key><string>HistoryFixtureProbe</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>
EOF
wattson_run_timeout 240 xcrun swiftc "$src"/Core/*.swift "$src"/MenuBar/*.swift "$src"/Popover/*.swift "$run_dir/probe.swift" -D DEBUG -swift-version 5 -warnings-as-errors -framework AppKit -framework CoreGraphics -framework IOKit -o "$app/Contents/MacOS/HistoryFixtureProbe" > "$share/results/probe-build.log" 2>&1
wattson_run_timeout 30 codesign --force --sign - --entitlements "$src/BatteryPowerApp.entitlements" "$app" >> "$share/results/probe-build.log" 2>&1
printf 'bundleID=%s\nsandboxed=true\nfrozenSourceCommit=8300cabcb5859fcc74c3ff613a2c530a47c01f30\n' "$identifier" > "$share/results/provenance.txt"
shasum -a 256 "$src"/Core/*.swift "$src"/MenuBar/*.swift "$src"/Popover/*.swift "$run_dir/probe.swift" "$src/BatteryPowerApp.entitlements" "$app/Contents/MacOS/HistoryFixtureProbe" > "$share/results/probe-inputs.sha256"
output="$HOME/Library/Containers/$identifier/Data/Library/Application Support/HistoryFixtureEvidence"
wattson_run_timeout 360 /usr/bin/env WATTSON_FORCE_LEGACY_KNOB=0 WATTSON_FORCE_REDUCE_MOTION=0 WATTSON_FORCE_REDUCE_TRANSPARENCY=0 WATTSON_FORCE_INCREASE_CONTRAST=0 "$app/Contents/MacOS/HistoryFixtureProbe" "$output" > "$share/results/probe-run.log" 2> "$share/results/probe-run.err"
[[ -d "$output" ]]
cp -R "$output" "$share/results/probe"
python3 "$snapshot/source-manifest.py" verify "$src" "$snapshot/frozen-source-inputs.sha256" "$share/results/source-after.json"
wattson_run_timeout 15 "$run_dir/DisplayProbe" > "$share/results/system-after.json"
python3 - "$share/results" <<'PY'
import json, pathlib, sys
result = pathlib.Path(sys.argv[1])
before = json.loads((result / 'system-before.json').read_text())
after = json.loads((result / 'system-after.json').read_text())
assert before == after, (before, after)
files = sorted(str(p.relative_to(result / 'probe')) for p in (result / 'probe').rglob('*.json'))
assert files, 'Probe produced no JSON evidence'
(result / 'diagnostic-results.json').write_text(json.dumps({'schema': 1, 'executionPassed': True, 'jsonEvidence': files, 'systemAccessibilityUnchanged': True, 'systemAccessibilityWritten': False, 'interpretation': 'Diagnostic execution and artifact collection only; findings remain in the probe JSON.'}, indent=2) + '\n')
PY
printf 'HISTORY_FIXTURE_DIAGNOSTIC_COMPLETED\n'
