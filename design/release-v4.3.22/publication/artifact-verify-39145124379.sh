#!/bin/bash
# Candidate bytes only: no build, installation, product launch, or publication.
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EVIDENCE="$ROOT/design/release-v4.3.22/publication"
source "$ROOT/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$ROOT/.build/artifact-v4.3.22.noindex"
artifact_workspace="$(/usr/bin/mktemp -d "$ROOT/.build/artifact-v4.3.22.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$artifact_workspace"
mkdir "$artifact_workspace/tmp"
export TMPDIR="$artifact_workspace/tmp"
export GODEBUG=http2client=0
unset WATTSON_RELEASE_BUILD_ROOT
export WATTSON_EXPECT_INSTALLER_SIGNED=0
export WATTSON_EXPECT_DMG_SIGNED=0
export WATTSON_EXPECT_NOTARIZED=0
export WATTSON_EXPECT_TEAM_ID=""
transfer="$EVIDENCE/artifact-transfer-39145124379.py"
inspect="$EVIDENCE/artifact-inspect-39145124379.py"
final="$ROOT/dist/github-candidate-v4.3.22-39145124379"
test ! -e "$final" || { echo 'Refusing to overwrite retained candidate inputs.' >&2; exit 1; }
printf '%s\n' "$artifact_workspace" > "$EVIDENCE/artifact-workspace-39145124379.txt"
wattson_run_timeout 160 /usr/bin/python3 "$inspect" snapshot "$artifact_workspace" "$EVIDENCE/artifact-before-39145124379.json"
ready=0
query_failures=0
for attempt in $(/usr/bin/seq 1 40); do
    status=0
    wattson_run_timeout 150 /usr/bin/python3 "$transfer" ready "$artifact_workspace" || status=$?
    if test "$status" = 0; then ready=1; break; fi
    if test "$status" = 4; then
        query_failures=$((query_failures + 1))
        test "$query_failures" -lt 3 || exit 4
    else
        query_failures=0
    fi
    test "$status" != 4 || { /bin/sleep 30; continue; }
    test "$status" = 3 || exit "$status"
    /bin/sleep 30
done
test "$ready" = 1 || { echo 'Bounded wait ended before build/artifact readiness.' >&2; exit 1; }
wattson_run_timeout 420 /usr/bin/python3 "$transfer" download "$artifact_workspace"
frozen="$artifact_workspace/frozen"
mkdir "$frozen"
wattson_run_timeout 20 /usr/bin/git -C "$ROOT" archive --format=tar --output="$artifact_workspace/frozen.tar" \
    7f41533b017d26519a69d541d3ffd2dea587f413 VERSION BatteryPowerApp.entitlements \
    scripts/verify_release.sh scripts/verify_dmg.sh scripts/lib/local_cleanup.sh scripts/lib/run_owned.py
wattson_run_timeout 20 /usr/bin/tar -xf "$artifact_workspace/frozen.tar" -C "$frozen"
wattson_run_timeout 20 /usr/bin/shasum -a 256 "$frozen/VERSION" "$frozen/BatteryPowerApp.entitlements" \
    "$frozen/scripts/verify_release.sh" "$frozen/scripts/verify_dmg.sh" \
    "$frozen/scripts/lib/local_cleanup.sh" "$frozen/scripts/lib/run_owned.py" \
    > "$EVIDENCE/artifact-frozen-input-hashes-39145124379.txt"
pkg="$artifact_workspace/assets/Wattson-v4.3.22-macos-universal.pkg"
dmg="$artifact_workspace/assets/Wattson-v4.3.22-macos-universal.dmg"
echo 'Running frozen standalone verify_release.sh on uploaded PKG and DMG.'
wattson_run_script "$frozen/scripts/verify_release.sh" "$pkg" "$dmg" \
    > "$EVIDENCE/artifact-real-verify-39145124379.log" 2>&1
/usr/bin/grep -Fx 'Verified Wattson 4.3.22: full PKG and DMG contain byte-identical apps' \
    "$EVIDENCE/artifact-real-verify-39145124379.log" >/dev/null \
    || { echo 'Verifier did not reach its full completion marker.' >&2; exit 1; }
wattson_run_timeout 300 /usr/bin/python3 "$inspect" signatures "$pkg" "$dmg" "$artifact_workspace" \
    "$frozen/BatteryPowerApp.entitlements" "$EVIDENCE/artifact-signatures-39145124379.json"
/bin/mv "$artifact_workspace/assets" "$final"
echo 'Real verification and actual signatures passed; exact four assets retained.'
# EXIT uses the shared owner to unregister disposable Apps, detach mounts and remove scratch.
