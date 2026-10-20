#!/bin/bash
# GUI-only production-renderer captures for a disposable VM or hosted runner.
# The caller owns final evidence; this invocation owns every runnable resource.
set -euo pipefail
unset PYTHONOPTIMIZE
export PYTHONDONTWRITEBYTECODE=1
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$#" != 1 ]]; then
    echo 'usage: verify_display_settings.sh NEW_EVIDENCE_DIRECTORY_UNDER_PROJECT' >&2
    exit 64
fi
OUTPUT="$(/usr/bin/python3 - "$ROOT_DIR" "$1" <<'PY'
import pathlib,sys
root=pathlib.Path(sys.argv[1]).resolve();path=pathlib.Path(sys.argv[2])
if not path.is_absolute(): path=root/path
path=path.resolve()
if root not in path.parents or path.exists(): raise SystemExit('Evidence must be a new directory under the project.')
print(path)
PY
)"
if [[ -e /Applications/Wattson.app || -e /Library/PrivilegedHelperTools/com.leoarrow.wattson.helper || -e /var/run/wattson-helper.sock ]]; then
    echo 'Use a disposable GUI environment without the canonical installation.' >&2
    exit 1
fi
[[ "$(launchctl managername)" == Aqua ]]
/usr/bin/pgrep -x WindowServer >/dev/null
[[ -z "$(git -C "$ROOT_DIR" status --porcelain -- Core MenuBar Popover scripts/verify_display_settings.sh scripts/lib/local_cleanup.sh scripts/lib/run_owned.py tests/visual/capture_display_settings.swift tests/test_settings_window_contract.py tests/local_runtime.py design/settings/display-refinement/qa/capture-compositor.py design/icon/in-app-logo)" ]]

source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$OUTPUT" "$ROOT_DIR/.build/display-capture.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/display-capture.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
APP="$BUILD_DIR/DisplayCapture.app"
IDENTIFIER="com.leoarrow.wattson.displayqa.$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
wattson_cleanup_add_defaults "$IDENTIFIER"
wattson_cleanup_add_container "$IDENTIFIER"
wattson_cleanup_add_app "$APP"
wattson_cleanup_add_executable "$APP/Contents/MacOS/DisplayCapture"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleName</key><string>DisplayCapture</string><key>CFBundleIdentifier</key><string>$IDENTIFIER</string><key>CFBundleExecutable</key><string>DisplayCapture</string><key>CFBundlePackageType</key><string>APPL</string><key>NSPrincipalClass</key><string>NSApplication</string><key>CFBundleShortVersionString</key><string>Fixture</string></dict></plist>
EOF
for logo in AppLogoColor.png AppLogoClearLight.png AppLogoClearDark.png; do
    cp "$ROOT_DIR/design/icon/in-app-logo/$logo" "$APP/Contents/Resources/$logo"
done
/usr/bin/sw_vers > "$OUTPUT/environment.txt"
/usr/bin/xcrun swift --version >> "$OUTPUT/environment.txt"
/usr/bin/xcrun --sdk macosx --show-sdk-version >> "$OUTPUT/environment.txt"
/usr/bin/uname -m >> "$OUTPUT/environment.txt"
git -C "$ROOT_DIR" rev-parse HEAD > "$OUTPUT/frozen-source-commit.txt"
shasum -a 256 "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift "$ROOT_DIR"/Popover/*.swift "$ROOT_DIR/tests/visual/capture_display_settings.swift" "$ROOT_DIR/tests/test_settings_window_contract.py" "$ROOT_DIR/tests/local_runtime.py" "$ROOT_DIR/design/settings/display-refinement/qa/capture-compositor.py" "$ROOT_DIR/scripts/verify_display_settings.sh" "$ROOT_DIR/scripts/lib/local_cleanup.sh" "$ROOT_DIR/scripts/lib/run_owned.py" "$ROOT_DIR"/design/icon/in-app-logo/*.png > "$OUTPUT/source-inputs.sha256"
wattson_run_timeout 180 xcrun swiftc "$ROOT_DIR"/Core/*.swift "$ROOT_DIR"/MenuBar/*.swift "$ROOT_DIR"/Popover/*.swift "$ROOT_DIR/tests/visual/capture_display_settings.swift" -swift-version 5 -D DEBUG -warnings-as-errors -framework AppKit -framework CoreGraphics -framework IOKit -o "$APP/Contents/MacOS/DisplayCapture" > "$OUTPUT/build.log" 2>&1
wattson_run codesign --force --sign - "$APP" > "$OUTPUT/sign.log" 2>&1
wattson_run codesign --verify --deep --strict "$APP" >> "$OUTPUT/sign.log" 2>&1

DRIVER="$ROOT_DIR/design/settings/display-refinement/qa/capture-compositor.py"
for variant in baseline high-contrast reduce-transparency; do
    contrast=0; transparency=0
    [[ "$variant" != high-contrast ]] || contrast=1
    [[ "$variant" != reduce-transparency ]] || transparency=1
    wattson_run_timeout 240 /usr/bin/env WATTSON_FORCE_INCREASE_CONTRAST="$contrast" WATTSON_FORCE_REDUCE_TRANSPARENCY="$transparency" WATTSON_FORCE_REDUCE_MOTION=1 /usr/bin/python3 "$DRIVER" "$APP/Contents/MacOS/DisplayCapture" "$OUTPUT/after-$variant"
done
for mode in native-selected macos27-selected shared-settings; do
    wattson_run_timeout 240 /usr/bin/env WATTSON_FORCE_INCREASE_CONTRAST=0 WATTSON_FORCE_REDUCE_TRANSPARENCY=0 WATTSON_FORCE_REDUCE_MOTION=1 /usr/bin/python3 "$DRIVER" "$APP/Contents/MacOS/DisplayCapture" "$OUTPUT/after-$mode" "--$mode"
done
_WATTSON_RUNNER_STARTING=1
/usr/bin/python3 "$ROOT_DIR/scripts/lib/run_owned.py" --grace 65 --timeout 480 -- /usr/bin/env WATTSON_RUN_INTERACTION=1 PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s "$ROOT_DIR/tests" -p test_settings_window_contract.py -v > "$OUTPUT/settings-contract.log" 2> "$OUTPUT/settings-contract.err" &
_WATTSON_RUNNER_PID=$!
_wattson_runner_registered
wait "$_WATTSON_RUNNER_PID"
_WATTSON_RUNNER_PID=''
shasum -a 256 -c "$OUTPUT/source-inputs.sha256" > "$OUTPUT/source-verification.log"
/usr/bin/python3 - "$OUTPUT" <<'PY'
import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]);checks={};frames=[]
checks['nativeAssertionsCompleted']='all assertions complete' in (root/'settings-contract.log').read_text()
errors=(root/'settings-contract.err').read_text()
checks['nativeEightTestsPassed']=bool(re.search(r'Ran 8 tests in ',errors)) and '\nOK\n' in errors
for name,count in [('after-baseline',8),('after-high-contrast',8),('after-reduce-transparency',8),('after-native-selected',2),('after-macos27-selected',4),('after-shared-settings',4)]:
    directory=root/name;report=json.loads((directory/'capture-results.json').read_text());geometry=sorted(directory.glob('*-geometry.json'))
    checks[name]=report.get('allPassed') is True and report.get('captureCount')==count and len(list(directory.glob('*.png')))==count and len(geometry)==count
    frames.extend(json.loads(path.read_text()) for path in geometry)
checks['nativeGlassCorners']=True;checks['glassSurfacesPresentWhenEnabled']=True;checks['boxedControlsCorners']=True;checks['threeStylesAndSevenStates']=True;checks['naturalPreviewSizes']=True;checks['percentagePresentation']=True;checks['native27Canvas']=True
for frame in frames:
    fresh=frame['freshNativeGlassCornerRadius']
    surfaces=[surface for surface in frame['glassSurfaces'] if surface['identifier']=='settings.control-group.glass']
    if frame['glassEffective']: checks['glassSurfacesPresentWhenEnabled'] &= bool(surfaces)
    for surface in surfaces:
        checks['nativeGlassCorners'] &= abs(surface['cornerRadius']-fresh)<.01
        if 'boxedControlsCornerRadius' in surface: checks['boxedControlsCorners'] &= abs(surface['boxedControlsCornerRadius']-surface['cornerRadius'])<.01
    if frame['section']!='menu-bar-icon': continue
    views=frame['views'];images=[view for view in views if view['identifier'].startswith('settings.menu-bar-icon.preview.')]
    headers=[view for view in views if view['identifier'].startswith('settings.menu-bar-icon.state-label.')]
    checks['threeStylesAndSevenStates'] &= len(images)==21 and len(headers)==7
    checks['naturalPreviewSizes'] &= all(view['imageScaling']==2 and abs(view['frame'][2]-view['imageSize'][0])<=.5 and abs(view['frame'][3]-view['imageSize'][1])<=.5 for view in images)
    percentages=[view for view in views if view['identifier'].startswith('settings.menu-bar-icon.percentage.') and 'text' in view and not view['hidden']]
    checks['percentagePresentation'] &= len(percentages)==(14 if frame['showsPercentage'] else 0) and not any('.macos27.' in view['identifier'] for view in percentages)
    checks['native27Canvas'] &= all(view['imageSize']==[25,16] and view['imageScaling']==2 for view in images if '.macos27.' in view['identifier'])
report={'schema':1,'allPassed':all(checks.values()),'captureCount':len(frames),'checks':checks}
(root/'gate-results.json').write_text(json.dumps(report,indent=2)+'\n');assert report['allPassed'],checks
PY
printf 'DISPLAY_SETTINGS_GUI_CHECKS_PASSED count=34 nativeTests=8\n'
