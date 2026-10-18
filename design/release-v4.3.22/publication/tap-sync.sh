#!/bin/bash
# Trusted, checksum-bound cask sync; own the disposable checkout until exit.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
evidence="$repo/design/release-v4.3.22/publication"
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$repo/.build/tap-sync.noindex"
scratch="$(mktemp -d "$repo/.build/tap-sync.noindex/work.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
return_status() { return "$1"; }
finish() {
    local status=$?
    trap - EXIT
    trap '' HUP INT TERM
    set +e
    (return_status "$status"; _wattson_cleanup)
    status=$?
    [[ ! -e "$scratch" ]] || status=1
    printf '%s\n' "$status" > "$evidence/tap-sync-exit-code.txt"
    printf '%s\n' "$([[ ! -e "$scratch" ]] && echo true || echo false)" > "$evidence/tap-checkout-cleaned.txt"
    exit "$status"
}
trap finish EXIT
python3 - "$evidence" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
r = json.loads((p/'release-created.json').read_text())
a = json.loads((p/'publish-attempt.json').read_text())
assert r['id'] == 416577205 and r['tag_name'] == 'v4.3.22'
assert r['draft'] is False and r['prerelease'] is False
assert a['allEightAssetDigestsMatch'] is True
pkg = [x for x in r['assets'] if x['name'] == 'Wattson-v4.3.22-macos-universal.pkg']
assert len(pkg) == 1
assert pkg[0]['digest'] == 'sha256:63a4b356a46d8aae086cb6045825f503ec937c7a7db4950bb74b6b1a1394b995'
PY
checkout="$scratch/tap"
wattson_run_timeout 120 git clone --single-branch --branch main git@github.com:laleoarrow/homebrew-tap.git "$checkout"
wattson_run_timeout 30 git -C "$checkout" ls-remote origin refs/heads/main > "$evidence/tap-remote-before-sync.txt"
base="$(git -C "$checkout" rev-parse HEAD)"
[[ "$(awk '{print $1}' "$evidence/tap-remote-before-sync.txt")" == "$base" ]]
printf '%s\n' "$base" > "$evidence/tap-base-commit.txt"
[[ -z "$(git -C "$checkout" status --porcelain)" ]]
cp "$checkout/Casks/wattson.rb" "$evidence/tap-cask-sync-before.rb"
python3 - "$checkout/Casks/wattson.rb" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]); old = p.read_text()
new, n = re.subn(r'^  version "[^"]+"$', '  version "4.3.22"', old, flags=re.M)
assert n == 1
new, n = re.subn(r'^  sha256 "[0-9a-f]{64}"$', '  sha256 "63a4b356a46d8aae086cb6045825f503ec937c7a7db4950bb74b6b1a1394b995"', new, flags=re.M)
assert n == 1 and new != old
assert sum(a != b for a, b in zip(old.splitlines(), new.splitlines())) == 2
assert len(old.splitlines()) == len(new.splitlines())
p.write_text(new)
PY
cp "$checkout/Casks/wattson.rb" "$evidence/tap-cask-after.rb"
wattson_run_timeout 30 ruby -c "$checkout/Casks/wattson.rb" > "$evidence/tap-ruby-syntax.log"
git -C "$checkout" diff --check
[[ "$(git -C "$checkout" status --porcelain)" == ' M Casks/wattson.rb' ]]
[[ "$(git -C "$checkout" diff --numstat)" == $'2\t2\tCasks/wattson.rb' ]]
git -C "$checkout" diff -- Casks/wattson.rb > "$evidence/tap-change.diff"
git -C "$checkout" add -- Casks/wattson.rb
wattson_run_timeout 60 git -C "$checkout" commit -m 'wattson 4.3.22' > "$evidence/tap-commit.log"
tap_commit="$(git -C "$checkout" rev-parse HEAD)"
[[ "$(git -C "$checkout" rev-parse HEAD^)" == "$base" ]]
[[ "$(git -C "$checkout" diff-tree --no-commit-id --name-only -r HEAD)" == 'Casks/wattson.rb' ]]
[[ "$(git -C "$checkout" diff-tree --no-commit-id --numstat -r HEAD)" == $'2\t2\tCasks/wattson.rb' ]]
[[ -z "$(git -C "$checkout" status --porcelain)" ]]
printf '%s\n' "$tap_commit" > "$evidence/tap-commit.txt"
git -C "$checkout" ls-tree -r HEAD > "$evidence/tap-tree-after.txt"
wattson_run_timeout 120 git -C "$checkout" push origin HEAD:refs/heads/main > "$evidence/tap-push.log" 2>&1
wattson_run_timeout 30 git -C "$checkout" ls-remote origin refs/heads/main > "$evidence/tap-remote-after-sync.txt"
[[ "$(awk '{print $1}' "$evidence/tap-remote-after-sync.txt")" == "$tap_commit" ]]
printf 'TAP_SYNC_PUSHED %s\n' "$tap_commit"
