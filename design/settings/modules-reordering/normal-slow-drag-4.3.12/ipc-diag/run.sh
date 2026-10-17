#!/bin/bash
set -euo pipefail
project='/Users/leoarrow/Project/mypackage/agents/电池功率'
source "$project/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
wattson_run_timeout 30 /usr/bin/python3 "$project/.build/normal-slow-drag.noindex/ipc-diag/host-run.py"
