#!/bin/bash
set -euo pipefail
share='/Volumes/My Shared Files/review'
snapshot='/Volumes/My Shared Files/snapshot'
source "$snapshot/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$HOME/Project/.release-v4.3.22-native.noindex" "$share/results"
run_dir="$(mktemp -d "$HOME/Project/.release-v4.3.22-native.noindex/run.XXXXXX")"
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
python3 - "$share/results/session.txt" <<'PY'
import pathlib,sys
assert 'Aqua' in pathlib.Path(sys.argv[1]).read_text()
PY
wattson_run_timeout 60 xcrun swiftc "$src/design/process-force-quit/native/display-probe.swift" -framework AppKit -o "$run_dir/DisplayProbe" > "$share/results/display-build.log" 2>&1
wattson_run_timeout 15 "$run_dir/DisplayProbe" > "$share/results/system-before.json"
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
    printf 'INTERACTION_%s_EXIT_STATUS %s\n' "$variant" "$interaction_status"
done
animation_status=0
/usr/bin/python3 "$src/scripts/lib/run_owned.py" --grace 65 --timeout 300 -- /bin/bash scripts/verify_animation_stress.sh > "$share/results/animation-stress.log" 2> "$share/results/animation-stress.err" &
_WATTSON_RUNNER_PID=$!
wait "$_WATTSON_RUNNER_PID" || animation_status=$?
_WATTSON_RUNNER_PID=''
printf '%s\n' "$animation_status" > "$share/results/animation-stress-exit-code.txt"
printf 'ANIMATION_STRESS_EXIT_STATUS %s\n' "$animation_status"
python3 "$snapshot/source-manifest.py" verify "$src" "$snapshot/frozen-source-inputs.sha256" "$share/results/source-after.json"
wattson_run_timeout 15 "$run_dir/DisplayProbe" > "$share/results/system-after.json"
python3 - "$share/results" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); before=json.loads((p/'system-before.json').read_text()); after=json.loads((p/'system-after.json').read_text())
animation=(p/'animation-stress.log').read_text()
checks={'animationExitZero':(p/'animation-stress-exit-code.txt').read_text().strip()=='0','animationFullPass':'ANIMATION_STRESS_PASSED iterations=20000 ' in animation,'systemAccessibilityUnchanged':before==after}
counts={}
for variant in ['baseline','legacy','accessibility']:
 interaction=(p/f'interaction-{variant}.log').read_text(); counts[variant]=interaction.count('✅')
 checks[f'{variant}ExitZero']=(p/f'interaction-{variant}-exit-code.txt').read_text().strip()=='0'
 checks[f'{variant}FullPass']='ALL_INTERACTION_CHECKS_PASSED' in interaction
 checks[f'{variant}ChecksAtLeast32']=counts[variant]>=32
(p/'gate-results.json').write_text(json.dumps({'schema':1,'allPassed':all(checks.values()),'checks':checks,'interactionChecks':counts,'systemAccessibilityWritten':False},indent=2)+'\n')
assert all(checks.values()),checks
PY
printf 'RELEASE_NATIVE_GATES_PASSED\n'
