#!/bin/bash
# Read official battery health through the production reader in the shipping sandbox.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ "$#" == 0 ]] || exit 64
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/system-health-probe.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/system-health-probe.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
APP_DIR="$BUILD_DIR/SystemHealthProbe.app"
TEST_BUNDLE_ID="com.leoarrow.wattson.systemhealthprobe.$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
wattson_cleanup_add_app "$APP_DIR"
wattson_cleanup_add_defaults "$TEST_BUNDLE_ID"
wattson_cleanup_add_container "$TEST_BUNDLE_ID"
wattson_cleanup_add_executable "$APP_DIR/Contents/MacOS/SystemHealthProbe"
mkdir -p "$APP_DIR/Contents/MacOS"
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>SystemHealthProbe</string>
<key>CFBundleIdentifier</key><string>$TEST_BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>SystemHealthProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
cat > "$BUILD_DIR/main.swift" <<'SWIFT'
import Foundation
let started = ProcessInfo.processInfo.systemUptime
let percent = SystemBatteryHealth.readLivePercent()
let result: [String: Any] = [
    "maximumCapacityPercent": percent.map { $0 as Any } ?? NSNull(),
    "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
    "containerHome": NSHomeDirectory().contains("/Library/Containers/"),
    "source": "production SystemBatteryHealth.readLivePercent",
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([10]))
SWIFT
wattson_run_timeout 90 /usr/bin/xcrun swiftc \
    "$ROOT_DIR/Core/SystemBatteryHealth.swift" "$BUILD_DIR/main.swift" \
    -swift-version 5 -warnings-as-errors -framework Foundation \
    -o "$APP_DIR/Contents/MacOS/SystemHealthProbe"
wattson_run /usr/bin/codesign --force --sign - \
    --entitlements "$ROOT_DIR/BatteryPowerApp.entitlements" "$APP_DIR"
wattson_run /usr/bin/codesign --verify --deep --strict "$APP_DIR"
/usr/bin/codesign -d --entitlements :- "$APP_DIR" > "$BUILD_DIR/actual-entitlements.plist" 2>/dev/null
/usr/bin/python3 - "$ROOT_DIR/BatteryPowerApp.entitlements" "$BUILD_DIR/actual-entitlements.plist" <<'PY'
import pathlib, plistlib, sys
expected, actual = [plistlib.loads(pathlib.Path(name).read_bytes()) for name in sys.argv[1:]]
assert actual == expected
assert actual['com.apple.security.app-sandbox'] is True
PY
probe_status=0
wattson_run_timeout 12 "$APP_DIR/Contents/MacOS/SystemHealthProbe" \
    > "$BUILD_DIR/result.json" 2> "$BUILD_DIR/probe.err" || probe_status=$?
/usr/bin/python3 - "$BUILD_DIR/result.json" "$ROOT_DIR/design/system-metric-authority/sandbox-health.json" \
    "$ROOT_DIR/Core/SystemBatteryHealth.swift" "$probe_status" <<'PY'
import datetime, hashlib, json, pathlib, sys
raw, output, source = map(pathlib.Path, sys.argv[1:4])
try:
    report = json.loads(raw.read_text())
except (ValueError, OSError):
    report = {'maximumCapacityPercent': None, 'containerHome': None}
report.update({
    'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'exactProductionEntitlementsVerified': True,
    'productionSourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'exitCode': int(sys.argv[4]),
    'expectedMaximumCapacityPercent': 84,
})
report['allPassed'] = (report['exitCode'] == 0 and report['maximumCapacityPercent'] == 84
                       and report['containerHome'] is True)
output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
print(json.dumps(report, sort_keys=True))
assert report['allPassed'], 'Sandboxed official battery health probe did not return the expected system reading'
PY
