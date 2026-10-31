#!/bin/bash
set -euo pipefail
WATTSON_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$WATTSON_ROOT/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
# No scratch, registration, preferences or mounts are created. The shared runner
# owns the verifier process and bounds transient public CDN retries.
wattson_run_timeout 600 /usr/bin/python3 \
  "$WATTSON_ROOT/design/release-v5.0.3/publication/verify-public-artwork.py" "$@"
