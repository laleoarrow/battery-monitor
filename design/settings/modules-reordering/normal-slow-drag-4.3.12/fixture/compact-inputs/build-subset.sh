#!/bin/bash
# Future reproducible derivation only; does not replace an existing sealed set.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
names=(source-5d5c896b7a15-native-build-inputs-subset.tar.gz subset-member-mapping.json MEMBER_SHA256SUMS.txt)
for name in "${names[@]}"; do [[ ! -e "$here/$name" && ! -L "$here/$name" ]] || exit 65; done
run_dir="$(mktemp -d "$here/subset-build.XXXXXX")"
wattson_cleanup_add_dir "$run_dir"
wattson_run_timeout 120 /usr/bin/env WATTSON_SUBSET_OUTPUT="$run_dir" /usr/bin/python3 "$here/build-subset.py"
# Publish only fully verified immutable artifacts. Scratch remains owned on all exits.
for name in "${names[@]}"; do /bin/mv "$run_dir/$name" "$here/$name"; done
