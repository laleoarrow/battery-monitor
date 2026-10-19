#!/bin/bash
set -euo pipefail
unset PYTHONOPTIMIZE
export PYTHONDONTWRITEBYTECODE=1
share='/Volumes/My Shared Files/review'
snapshot='/Volumes/My Shared Files/snapshot'
source "$snapshot/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$HOME/Project/.display-settings.noindex" "$share/results"
run_dir="$(mktemp -d "$HOME/Project/.display-settings.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$run_dir"
[[ ! -e /Applications/Wattson.app && ! -e /Library/PrivilegedHelperTools/com.leoarrow.wattson.helper && ! -e /var/run/wattson-helper.sock ]]
sw_vers > "$share/results/system.txt"
xcrun swift --version >> "$share/results/system.txt"
[[ "$(launchctl managername)" == Aqua ]]
for phase in before after; do
    [[ "$(shasum -a 256 "$snapshot/$phase.tar.gz" | awk '{print $1}')" == "$(cat "$snapshot/$phase.sha256")" ]]
    mkdir "$run_dir/$phase"
    tar -xzf "$snapshot/$phase.tar.gz" -C "$run_dir/$phase"
    src="$run_dir/$phase"
    python3 "$snapshot/source-manifest.py" verify "$src" "$snapshot/$phase-inputs.sha256" "$share/results/$phase-source-before.json"
    app="$run_dir/$phase/DisplayCapture.app"
    identifier="com.leoarrow.wattson.displayqa.$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
    wattson_cleanup_add_defaults "$identifier"
    wattson_cleanup_add_container "$identifier"
    wattson_cleanup_add_app "$app"
    wattson_cleanup_add_executable "$app/Contents/MacOS/DisplayCapture"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleName</key><string>DisplayCapture</string><key>CFBundleIdentifier</key><string>$identifier</string><key>CFBundleExecutable</key><string>DisplayCapture</string><key>CFBundlePackageType</key><string>APPL</string><key>NSPrincipalClass</key><string>NSApplication</string><key>CFBundleShortVersionString</key><string>Fixture</string></dict></plist>
EOF
    for logo in AppLogoColor.png AppLogoClearLight.png AppLogoClearDark.png; do
        cp "$src/design/icon/in-app-logo/$logo" "$app/Contents/Resources/$logo"
    done
    wattson_run_timeout 180 xcrun swiftc "$src"/Core/*.swift "$src"/MenuBar/*.swift "$src"/Popover/*.swift "$snapshot/capture_display_settings.swift" -swift-version 5 -D DEBUG -warnings-as-errors -framework AppKit -framework CoreGraphics -framework IOKit -o "$app/Contents/MacOS/DisplayCapture" > "$share/results/$phase-build.log" 2>&1
    wattson_run codesign --force --sign - "$app" > "$share/results/$phase-sign.log" 2>&1
    before_arg=()
    [[ "$phase" != before ]] || before_arg=(--before)
    for variant in baseline high-contrast reduce-transparency; do
        [[ "$phase" != before || "$variant" == baseline ]] || continue
        contrast=0; transparency=0
        [[ "$variant" != high-contrast ]] || contrast=1
        [[ "$variant" != reduce-transparency ]] || transparency=1
        wattson_run_timeout 240 /usr/bin/env WATTSON_FORCE_INCREASE_CONTRAST="$contrast" WATTSON_FORCE_REDUCE_TRANSPARENCY="$transparency" WATTSON_FORCE_REDUCE_MOTION=1 /usr/bin/python3 "$snapshot/capture-compositor.py" "$app/Contents/MacOS/DisplayCapture" "$share/results/$phase-$variant" ${before_arg[@]+"${before_arg[@]}"}
    done
    if [[ "$phase" == after ]]; then
        wattson_run_timeout 240 /usr/bin/env WATTSON_FORCE_INCREASE_CONTRAST=0 WATTSON_FORCE_REDUCE_TRANSPARENCY=0 WATTSON_FORCE_REDUCE_MOTION=1 /usr/bin/python3 "$snapshot/capture-compositor.py" "$app/Contents/MacOS/DisplayCapture" "$share/results/after-native-selected" --native-selected
        wattson_run_timeout 240 /usr/bin/env WATTSON_FORCE_INCREASE_CONTRAST=0 WATTSON_FORCE_REDUCE_TRANSPARENCY=0 WATTSON_FORCE_REDUCE_MOTION=1 /usr/bin/python3 "$snapshot/capture-compositor.py" "$app/Contents/MacOS/DisplayCapture" "$share/results/after-macos27-selected" --macos27-selected
        wattson_run_timeout 240 /usr/bin/env WATTSON_FORCE_INCREASE_CONTRAST=0 WATTSON_FORCE_REDUCE_TRANSPARENCY=0 WATTSON_FORCE_REDUCE_MOTION=1 /usr/bin/python3 "$snapshot/capture-compositor.py" "$app/Contents/MacOS/DisplayCapture" "$share/results/after-shared-settings" --shared-settings
        cd "$src"
        _WATTSON_RUNNER_STARTING=1
        /usr/bin/python3 "$src/scripts/lib/run_owned.py" --grace 65 --timeout 360 -- /usr/bin/env WATTSON_RUN_INTERACTION=1 PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s tests -p test_settings_window_contract.py -v > "$share/results/settings-contract.log" 2> "$share/results/settings-contract.err" &
        _WATTSON_RUNNER_PID=$!
        _wattson_runner_registered
        wait "$_WATTSON_RUNNER_PID"
        _WATTSON_RUNNER_PID=''
    fi
    python3 "$snapshot/source-manifest.py" verify "$src" "$snapshot/$phase-inputs.sha256" "$share/results/$phase-source-after.json"
done
printf 'DISPLAY_SETTINGS_CAPTURE_AND_NATIVE_CONTRACT_PASSED\n'
