#!/bin/bash
set -euo pipefail
share='/Volumes/My Shared Files/review'
snapshot='/Volumes/My Shared Files/snapshot'
source "$snapshot/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$HOME/Project/.focus-native.noindex" "$share/results"
run_dir="$(mktemp -d "$HOME/Project/.focus-native.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$run_dir"
[[ "$(shasum -a 256 "$snapshot/source.tar.gz" | awk '{print $1}')" == "$(cat "$snapshot/source.sha256")" ]]
mkdir "$run_dir/source"
tar -xzf "$snapshot/source.tar.gz" -C "$run_dir/source"
src="$run_dir/source"
python3 "$snapshot/source-manifest.py" verify "$src" "$snapshot/frozen-source-inputs.sha256" "$share/results/source-before.json"
[[ ! -e /Applications/Wattson.app && ! -e /Library/PrivilegedHelperTools/com.leoarrow.wattson.helper && ! -e /var/run/wattson-helper.sock ]]
sw_vers > "$share/results/system.txt"
xcrun swift --version >> "$share/results/system.txt"
launchctl managername > "$share/results/session.txt"
[[ "$(cat "$share/results/session.txt")" == Aqua ]]
wattson_run_timeout 60 xcrun swiftc "$src/design/process-force-quit/native/display-probe.swift" -framework AppKit -o "$run_dir/DisplayProbe" > "$share/results/display-build.log" 2>&1
wattson_run_timeout 15 "$run_dir/DisplayProbe" > "$share/results/system-before.json"
mode="$(cat "$snapshot/mode.txt")"
app="$run_dir/FocusProbe.app"
identifier="com.leoarrow.wattson.focusqa.$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
export WATTSON_TEST_DEFAULTS_SUITE="Wattson.FocusQA.$(/usr/bin/uuidgen)"
wattson_cleanup_add_defaults "$WATTSON_TEST_DEFAULTS_SUITE"
wattson_cleanup_add_container "$identifier"
wattson_cleanup_add_app "$app"
mkdir -p "$app/Contents/MacOS" "$run_dir/home"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleName</key><string>FocusProbe</string><key>CFBundleIdentifier</key><string>$identifier</string><key>CFBundleExecutable</key><string>FocusProbe</string><key>CFBundlePackageType</key><string>APPL</string><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>
EOF
wattson_run_timeout 180 xcrun swiftc "$src"/Core/*.swift "$src"/MenuBar/*.swift "$src"/Popover/*.swift "$snapshot/main.swift" -D DEBUG -framework AppKit -framework CoreGraphics -framework IOKit -o "$app/Contents/MacOS/FocusProbe" > "$share/results/focus-build.log" 2>&1
wattson_run codesign --force --sign - --entitlements "$src/BatteryPowerApp.entitlements" "$app" > "$share/results/focus-sign.log" 2>&1
wattson_run_timeout 30 /usr/bin/env CFFIXED_USER_HOME="$run_dir/home" "$app/Contents/MacOS/FocusProbe" > "$share/results/focus.log" 2> "$share/results/focus.err"
python3 - "$share/results/focus.log" "$share/results/focus-results.json" "$mode" <<'PY'
import json,pathlib,sys
lines=pathlib.Path(sys.argv[1]).read_text().splitlines()
items=[s.removeprefix('FOCUS_PROBE_JSON ') for s in lines if s.startswith('FOCUS_PROBE_JSON ')]
assert len(items)==1
report=json.loads(items[0]);pathlib.Path(sys.argv[2]).write_text(json.dumps(report,indent=2)+'\n')
if sys.argv[3]=='full': assert report['allPassed'],report
PY
if [[ "$mode" == full ]]; then
    cd "$src"
    for variant in baseline legacy accessibility; do
        legacy=0; motion=0; transparency=0
        [[ "$variant" == baseline ]] || legacy=1
        if [[ "$variant" == accessibility ]]; then motion=1; transparency=1; fi
        interaction_status=0
        /usr/bin/python3 "$src/scripts/lib/run_owned.py" --grace 65 --timeout 600 -- /usr/bin/env WATTSON_FORCE_LEGACY_KNOB="$legacy" WATTSON_FORCE_REDUCE_MOTION="$motion" WATTSON_FORCE_REDUCE_TRANSPARENCY="$transparency" WATTSON_FORCE_INCREASE_CONTRAST=0 /bin/bash scripts/verify_interaction.sh > "$share/results/interaction-$variant.log" 2> "$share/results/interaction-$variant.err" &
        _WATTSON_RUNNER_PID=$!
        wait "$_WATTSON_RUNNER_PID" || interaction_status=$?
        _WATTSON_RUNNER_PID=''
        printf '%s\n' "$interaction_status" > "$share/results/interaction-$variant-exit-code.txt"
    done
    animation_status=0
    /usr/bin/python3 "$src/scripts/lib/run_owned.py" --grace 65 --timeout 300 -- /bin/bash scripts/verify_animation_stress.sh > "$share/results/animation-stress.log" 2> "$share/results/animation-stress.err" &
    _WATTSON_RUNNER_PID=$!
    wait "$_WATTSON_RUNNER_PID" || animation_status=$?
    _WATTSON_RUNNER_PID=''
    printf '%s\n' "$animation_status" > "$share/results/animation-stress-exit-code.txt"
    python3 - "$share/results" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);checks={};counts={}
for v in ['baseline','legacy','accessibility']:
 s=(p/f'interaction-{v}.log').read_text();counts[v]=s.count('✅');checks[v]=(p/f'interaction-{v}-exit-code.txt').read_text().strip()=='0' and 'ALL_INTERACTION_CHECKS_PASSED' in s
checks['animationStress']=(p/'animation-stress-exit-code.txt').read_text().strip()=='0' and 'ANIMATION_STRESS_PASSED iterations=20000 ' in (p/'animation-stress.log').read_text()
(p/'gate-results.json').write_text(json.dumps({'allPassed':all(checks.values()),'checks':checks,'counts':counts},indent=2)+'\n')
assert all(checks.values()),checks
PY
fi
wattson_run_timeout 15 "$run_dir/DisplayProbe" > "$share/results/system-after.json"
python3 - "$share/results" <<'PYEND'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);before=json.loads((p/'system-before.json').read_text());after=json.loads((p/'system-after.json').read_text())
checks={'accessibilityUnchanged':before==after}
(p/'system-unchanged.json').write_text(json.dumps({'allPassed':all(checks.values()),'checks':checks},indent=2)+'\n')
assert all(checks.values()),checks
PYEND
python3 "$snapshot/source-manifest.py" verify "$src" "$snapshot/frozen-source-inputs.sha256" "$share/results/source-after.json"
printf 'FOCUS_NATIVE_EXECUTION_COMPLETE mode=%s\n' "$mode"
