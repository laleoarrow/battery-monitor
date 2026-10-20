#!/bin/bash
# Verify one successful frozen community candidate; no build/install/publication.
set -euo pipefail
umask 077
if [[ "$#" != 3 || ! "$1" =~ ^[1-9][0-9]+$ || ! "$2" =~ ^[0-9a-f]{40}$ || ! "$3" =~ ^[1-9][0-9]+$ ]]; then
    echo 'usage: /bin/bash artifact-verify.sh CANDIDATE-RUN-ID SOURCE-SHA HEADLESS-RUN-ID' >&2
    exit 2
fi
RUN="$1"
readonly RUN
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EVIDENCE="$ROOT/design/release-v5.0.0/publication"
SOURCE_SHA="$2"
readonly SOURCE_SHA
export WATTSON_RELEASE_SOURCE_SHA="$SOURCE_SHA"
export WATTSON_RELEASE_HEADLESS_RUN_ID="$3"
source "$ROOT/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
final="$ROOT/dist/github-candidate-v5.0.0-$RUN"
[[ ! -e "$final" && ! -L "$final" ]] || {
    echo 'Refusing to overwrite retained candidate inputs.' >&2; exit 1;
}
[[ ! -L "$ROOT/dist" ]] || { echo 'dist must not be a symlink.' >&2; exit 1; }
mkdir -p "$ROOT/dist" "$ROOT/.build/artifact-v5.0.0.noindex"
artifact_workspace="$(/usr/bin/mktemp -d "$ROOT/.build/artifact-v5.0.0.noindex/run.XXXXXX")"
wattson_cleanup_add_dir "$artifact_workspace"
record="$(/usr/bin/mktemp -d "$EVIDENCE/artifact-$RUN-review.XXXXXX")"
mkdir "$artifact_workspace/tmp"
export TMPDIR="$artifact_workspace/tmp"
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONOPTIMIZE
export GODEBUG=http2client=0
unset WATTSON_RELEASE_BUILD_ROOT
export WATTSON_EXPECT_INSTALLER_SIGNED=0
export WATTSON_EXPECT_DMG_SIGNED=0
export WATTSON_EXPECT_NOTARIZED=0
export WATTSON_EXPECT_TEAM_ID=""
printf '%s\n' "$artifact_workspace" > "$record/artifact-workspace.txt"
transfer="$EVIDENCE/artifact-transfer.py"
inspect="$EVIDENCE/artifact-inspect.py"
echo "Artifact evidence: $record"
wattson_run_timeout 160 /usr/bin/python3 "$inspect" snapshot "$artifact_workspace" "$record/artifact-before.json"
# One readiness check; incomplete/failed candidates are never downloaded.
wattson_run_timeout 240 /usr/bin/python3 "$transfer" ready "$RUN" "$artifact_workspace" "$record"
wattson_run_timeout 420 /usr/bin/python3 "$transfer" download "$RUN" "$artifact_workspace" "$record"
frozen="$artifact_workspace/frozen"
mkdir "$frozen"
wattson_run_timeout 20 /usr/bin/git -C "$ROOT" archive --format=tar --output="$artifact_workspace/frozen.tar" \
    "$SOURCE_SHA" VERSION BatteryPowerApp.entitlements \
    scripts/verify_release.sh scripts/verify_dmg.sh scripts/lib/local_cleanup.sh scripts/lib/run_owned.py
wattson_run_timeout 20 /usr/bin/tar -xf "$artifact_workspace/frozen.tar" -C "$frozen"
[[ "$(/usr/bin/tr -d '\r\n' < "$frozen/VERSION")" == 5.0.0 ]]
wattson_run_timeout 20 /usr/bin/shasum -a 256 "$frozen/VERSION" "$frozen/BatteryPowerApp.entitlements" \
    "$frozen/scripts/verify_release.sh" "$frozen/scripts/verify_dmg.sh" \
    "$frozen/scripts/lib/local_cleanup.sh" "$frozen/scripts/lib/run_owned.py" \
    > "$record/artifact-frozen-input-hashes.txt"
pkg="$artifact_workspace/assets/Wattson-v5.0.0-macos-universal.pkg"
dmg="$artifact_workspace/assets/Wattson-v5.0.0-macos-universal.dmg"
echo 'Running frozen standalone verify_release.sh on uploaded PKG and DMG.'
wattson_run_script "$frozen/scripts/verify_release.sh" "$pkg" "$dmg" \
    > "$record/artifact-real-verify.log" 2>&1
/usr/bin/grep -Fx 'Verified Wattson 5.0.0: full PKG and DMG contain byte-identical apps' \
    "$record/artifact-real-verify.log" >/dev/null \
    || { echo 'Verifier did not reach its full completion marker.' >&2; exit 1; }
wattson_run_timeout 300 /usr/bin/python3 "$inspect" signatures "$pkg" "$dmg" "$artifact_workspace" \
    "$frozen/BatteryPowerApp.entitlements" "$record/artifact-signatures.json"
wattson_run_timeout 160 /usr/bin/python3 "$inspect" snapshot "$artifact_workspace" "$record/artifact-after.json"
wattson_run_timeout 20 /usr/bin/python3 "$EVIDENCE/artifact-proof.py" "$record" "$final" "$RUN"
/bin/mv "$artifact_workspace/assets" "$final"
echo "Verified exact candidate assets retained: $final"
# Shared EXIT unregisters expanded Apps, detaches verifier mounts and removes scratch.
