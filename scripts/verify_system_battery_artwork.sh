#!/bin/bash
# Bounded, no-window diagnostic. Final evidence belongs to the caller; this
# invocation owns and cleans only its scratch/compiler files and child processes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# != 1 ]]; then
    echo "usage: $0 new-evidence-directory" >&2
    exit 64
fi
EVIDENCE_DIR="$1"
if [[ -e "$EVIDENCE_DIR" || -L "$EVIDENCE_DIR" ]]; then
    echo "Evidence directory must not already exist: $EVIDENCE_DIR" >&2
    exit 64
fi
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/system-battery-artwork.noindex"
PROBE_SCRATCH="$(mktemp -d "$ROOT_DIR/.build/system-battery-artwork.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$PROBE_SCRATCH"
mkdir -p "$PROBE_SCRATCH/home" "$PROBE_SCRATCH/tmp" "$EVIDENCE_DIR"
EVIDENCE_DIR="$(cd "$EVIDENCE_DIR" && pwd)"
SOURCE_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD)"
SDK_VERSION="$(/usr/bin/xcrun --sdk macosx --show-sdk-version)"
export ROOT_DIR EVIDENCE_DIR SOURCE_SHA SDK_VERSION

cat > "$PROBE_SCRATCH/context.py" <<'PY'
import hashlib
import json
import os
import pathlib
import platform
import subprocess

root = pathlib.Path(os.environ["ROOT_DIR"])
def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()
catalog = pathlib.Path("/System/Library/CoreServices/ControlCenter.app/Contents/Resources/Assets.car")
context = {
    "sourceSHA": os.environ["SOURCE_SHA"],
    "sourceDirty": bool(subprocess.check_output(["git", "-C", str(root), "status", "--porcelain"], text=True)),
    "systemVersion": subprocess.check_output(["/usr/bin/sw_vers", "-productVersion"], text=True).strip(),
    "systemBuild": subprocess.check_output(["/usr/bin/sw_vers", "-buildVersion"], text=True).strip(),
    "sdkVersion": os.environ["SDK_VERSION"],
    "architecture": platform.machine(),
    "xcodeVersion": subprocess.check_output(["/usr/bin/xcodebuild", "-version"], text=True).strip(),
    "sourceFilesSHA256": {str(path.relative_to(root)): digest(path) for path in [
        root / "scripts/verify_system_battery_artwork.sh",
        root / "tests/visual/probe_system_battery_artwork.swift",
        root / "MenuBar/BatteryIcon.swift",
    ]},
    "catalog": {"path": str(catalog), "exists": catalog.is_file()},
}
if catalog.is_file():
    context["catalog"].update(sizeBytes=catalog.stat().st_size, sha256=digest(catalog))
(pathlib.Path(os.environ["EVIDENCE_DIR"]) / "context.json").write_text(json.dumps(context, indent=2, sort_keys=True) + "\n")
PY
wattson_run_timeout 15 /usr/bin/python3 "$PROBE_SCRATCH/context.py"

CATALOG_STATUS=0
wattson_run_timeout 30 /usr/bin/assetutil --info \
    /System/Library/CoreServices/ControlCenter.app/Contents/Resources/Assets.car \
    > "$PROBE_SCRATCH/catalog.json" 2> "$EVIDENCE_DIR/catalog-stderr.txt" || CATALOG_STATUS=$?
export CATALOG_STATUS PROBE_SCRATCH
cat > "$PROBE_SCRATCH/catalog.py" <<'PY'
import json
import os
import pathlib

source = pathlib.Path(os.environ["PROBE_SCRATCH"]) / "catalog.json"
result = {"assetutilExitStatus": int(os.environ["CATALOG_STATUS"]), "matches": []}
if result["assetutilExitStatus"] == 0:
    if source.stat().st_size > 32 * 1024 * 1024:
        raise SystemExit("Unexpected asset catalog metadata exceeds the 32 MiB bound")
    metadata = json.loads(source.read_text())
    if not isinstance(metadata, list):
        raise SystemExit("Unexpected asset catalog metadata shape")
    matches = [entry for entry in metadata if isinstance(entry, dict) and any(
        "battery" in value.lower() for key, value in entry.items()
        if isinstance(value, str) and key.lower() in ("name", "renditionname", "assetname")
    )]
    if len(matches) > 1000:
        raise SystemExit("Unexpected battery asset count exceeds the 1000-record bound")
    result.update(totalCatalogRecords=len(metadata), matches=matches)
(pathlib.Path(os.environ["EVIDENCE_DIR"]) / "catalog-battery.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
PY
wattson_run_timeout 10 /usr/bin/python3 "$PROBE_SCRATCH/catalog.py"

BINARY="$PROBE_SCRATCH/ProbeSystemBatteryArtwork"
wattson_cleanup_add_executable "$BINARY"
wattson_run_timeout 120 /usr/bin/env \
    CLANG_MODULE_CACHE_PATH="$PROBE_SCRATCH/module-cache" \
    /usr/bin/xcrun swiftc -warnings-as-errors \
    "$ROOT_DIR/tests/visual/probe_system_battery_artwork.swift" \
    -framework AppKit -framework CryptoKit -o "$BINARY" \
    > "$EVIDENCE_DIR/compile.log" 2>&1
wattson_run_timeout 30 /usr/bin/env \
    CFFIXED_USER_HOME="$PROBE_SCRATCH/home" TMPDIR="$PROBE_SCRATCH/tmp" \
    "$BINARY" "$EVIDENCE_DIR" 2>&1 | tee "$EVIDENCE_DIR/probe.log"
