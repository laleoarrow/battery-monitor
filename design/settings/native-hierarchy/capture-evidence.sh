#!/bin/bash
set -euo pipefail
share="${1:?usage: capture-evidence.sh SHARED_INPUT_DIRECTORY}"
source "$share/lifecycle/local_cleanup.sh"
wattson_cleanup_init
project="$HOME/WattsonSettingsReview"
mkdir -p "$project/.build/native-hierarchy.noindex"
run_root="$(mktemp -d "$project/.build/native-hierarchy.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$run_root"
mkdir -p "$run_root/source"
wattson_run_timeout 30 tar -xf "$share/source.tar" -C "$run_root/source"
cd "$run_root/source"
/usr/bin/python3 - "$share/source-manifest.json" <<'VERIFY_SOURCE'
from pathlib import Path
import hashlib, json, sys
manifest = json.loads(Path(sys.argv[1]).read_text())
assert all(hashlib.sha256(Path(name).read_bytes()).hexdigest() == value
           for name, value in manifest.items()), "Capture source hash mismatch"
VERIFY_SOURCE
wattson_run_timeout 10 /usr/bin/patch -p1 < "$share/capture-owned-windows.patch"
app="$PWD/.build/preview.noindex/Wattson Glass Preview.app"
wattson_cleanup_add_app "$app"
wattson_cleanup_add_executable "$app/Contents/MacOS/WattsonGlassPreview"
wattson_run_script scripts/build_glass_preview.sh --keep-app > "$share/build-preview.log" 2>&1
app_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
wattson_cleanup_add_container "$app_id"
for config in 'normal 0 0 0' 'reduced-transparency 0 1 0' 'increased-contrast 0 0 1' 'reduced-motion 1 0 0'; do
 read -r label motion transparency contrast <<< "$config"
 captures="$HOME/Library/Containers/$app_id/Data/Library/Caches/native-hierarchy-$label"
 mkdir -p "$captures"
 gallery_args=(--all-power-states)
 if [[ "$label" != normal ]]; then gallery_args+=(--settings-only); fi
 WATTSON_FORCE_REDUCE_MOTION="$motion" WATTSON_FORCE_REDUCE_TRANSPARENCY="$transparency" WATTSON_FORCE_INCREASE_CONTRAST="$contrast" wattson_run_timeout 240 "$app/Contents/MacOS/WattsonGlassPreview" --export-gallery "$captures" "${gallery_args[@]}" > "$share/$label-gallery.log" 2>&1
 mkdir -p "$share/$label"
 cp -R "$captures/" "$share/$label/"
 printf 'FINAL_GALLERY_COMPLETED=%s\n' "$label"
done
WATTSON_RUN_INTERACTION=1 WATTSON_FORCE_LEGACY_KNOB=0 WATTSON_FORCE_REDUCE_MOTION=0 WATTSON_FORCE_REDUCE_TRANSPARENCY=0 WATTSON_FORCE_INCREASE_CONTRAST=0 wattson_run_timeout 310 /usr/bin/python3 -m unittest discover -s tests -p test_settings_window_contract.py -v > "$share/settings-interaction.log" 2>&1
printf '%s\n' FINAL_SETTINGS_INTERACTION_PASSED
/usr/bin/sw_vers > "$share/system.txt"
/usr/bin/python3 - "$share/source-manifest.json" "$share/source-verify-after.json" <<'VERIFY_SOURCE'
from pathlib import Path
import hashlib, json, sys
manifest = json.loads(Path(sys.argv[1]).read_text())
checks = {name: hashlib.sha256(Path(name).read_bytes()).hexdigest() == value
          for name, value in manifest.items() if name != "tests/visual/glass_preview.swift"}
Path(sys.argv[2]).write_text(json.dumps(checks, indent=2) + "\n")
assert all(checks.values()), "Production source changed during capture"
VERIFY_SOURCE
printf '%s\n' FINAL_OWN_WINDOW_GALLERY_COMPLETE > "$share/completion.txt"
