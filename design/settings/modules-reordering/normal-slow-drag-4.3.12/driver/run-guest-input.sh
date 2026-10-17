#!/bin/bash
set -euo pipefail
[[ $# == 2 && "$HOME" == /Users/admin && "$(/usr/sbin/sysctl -n hw.model)" == VirtualMac* ]] || exit 64
share='/Volumes/My Shared Files/normaldrag'
source "$share/fixture/lifecycle/local_cleanup.sh"
wattson_cleanup_init
plan="$1"; output="$2"
/usr/bin/python3 - "$share/driver/results" "$output" <<'PY'
from pathlib import Path
import sys
base=Path(sys.argv[1]).resolve(strict=True); output=Path(sys.argv[2])
assert output.parent.resolve(strict=True)==base and not output.exists()
assert not output.is_symlink() and not any(c in str(output) for c in '\r\n')
for suffix in ('.compile.log','.source.sha256','.stdout','.stderr'):
    assert not Path(str(output)+suffix).exists()
PY
scratch="$(mktemp -d "$share/driver/compile.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
expected='6096f1adbc87caeee0354874ba45e5b39df9c7e8b15fd2c5fab0632a6472008d'
actual="$(/usr/bin/shasum -a 256 "$share/driver/GuestSlowInput.swift" | /usr/bin/awk '{print $1}')"
[[ "$actual" == "$expected" ]] || exit 65
printf '%s\n' "$actual" > "$output.source.sha256"
mkdir "$scratch/tmp"
wattson_run_timeout 120 /usr/bin/env TMPDIR="$scratch/tmp" /usr/bin/xcrun swiftc \
  -O -swift-version 5 -module-cache-path "$scratch/modules" \
  -framework AppKit -framework ApplicationServices -framework IOKit \
  "$share/driver/GuestSlowInput.swift" -o "$scratch/GuestSlowInput" > "$output.compile.log" 2>&1
if [[ "$plan" == --preflight ]]; then
  wattson_run_timeout 20 "$scratch/GuestSlowInput" --preflight > "$output" 2> "$output.stderr"
else
  [[ -f "$plan" && ! -L "$plan" ]] || exit 65
  wattson_run_timeout 20 "$scratch/GuestSlowInput" "$plan" "$output" > "$output.stdout" 2> "$output.stderr"
fi
