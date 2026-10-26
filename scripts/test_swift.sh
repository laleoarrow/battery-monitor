#!/bin/bash
# Own the Swift test process and every preference domain it creates.
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT_DIR/.build/swift-tests.noindex"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/.build/swift-tests.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$BUILD_DIR"
WATTSON_TEST_DEFAULTS_MANIFEST="$BUILD_DIR/defaults"
mkdir "$WATTSON_TEST_DEFAULTS_MANIFEST"
export WATTSON_TEST_DEFAULTS_MANIFEST
wattson_cleanup_add_defaults_manifest "$WATTSON_TEST_DEFAULTS_MANIFEST"

cd "$ROOT_DIR"
if [[ -n "${WATTSON_SWIFT_TEST_TIMEOUT:-}" ]]; then
    [[ "$WATTSON_SWIFT_TEST_TIMEOUT" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
        echo "WATTSON_SWIFT_TEST_TIMEOUT must be a number of seconds" >&2
        exit 2
    }
    wattson_run_timeout "$WATTSON_SWIFT_TEST_TIMEOUT" /usr/bin/env -u CFFIXED_USER_HOME swift test "$@"
else
    wattson_run /usr/bin/env -u CFFIXED_USER_HOME swift test "$@"
fi
