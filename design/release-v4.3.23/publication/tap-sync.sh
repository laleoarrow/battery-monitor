#!/bin/bash
# Prepare/commit/push only the public, checksum-bound Wattson cask when invoked.
set -euo pipefail
umask 077
if [[ "$#" != 1 || ! "$1" =~ ^[0-9a-f]{64}$ ]]; then
    echo 'usage: /bin/bash tap-sync.sh VERIFIED-PKG-SHA256' >&2
    exit 2
fi
PKG_SHA="$1"
readonly PKG_SHA
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
evidence="$repo/design/release-v4.3.23/publication"
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$repo/.build/tap-sync-v4.3.23.noindex"
scratch="$(mktemp -d "$repo/.build/tap-sync-v4.3.23.noindex/work.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
record="$(mktemp -d "$evidence/tap-sync-review.XXXXXX")"
mkdir "$scratch/tmp"
export TMPDIR="$scratch/tmp"
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONOPTIMIZE
export GIT_TERMINAL_PROMPT=0
printf '%s\n' "$scratch" > "$record/tap-workspace.txt"
[[ -f "$evidence/release-created.json" && ! -L "$evidence/release-created.json" ]] || {
    echo 'Verified release-created.json is required before tap synchronization.' >&2; exit 1;
}
wattson_run_timeout 45 gh api repos/laleoarrow/battery-monitor/releases/tags/v4.3.23 > "$scratch/live-release.json"
wattson_run_timeout 45 gh api repos/laleoarrow/battery-monitor/git/ref/tags/v4.3.23 > "$scratch/tag-ref.json"
TAG_OBJECT="$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["object"]["type"]=="tag"; print(d["object"]["sha"])' "$scratch/tag-ref.json")"
[[ "$TAG_OBJECT" =~ ^[0-9a-f]{40}$ ]]
wattson_run_timeout 45 gh api "repos/laleoarrow/battery-monitor/git/tags/$TAG_OBJECT" > "$scratch/tag-object.json"
wattson_run_timeout 45 gh api repos/laleoarrow/battery-monitor/git/ref/heads/main > "$scratch/main-ref.json"
/usr/bin/python3 - "$evidence" "$scratch" "$record" "$PKG_SHA" <<'PY'
import hashlib,json,re,sys
from pathlib import Path
p,scratch,record=map(Path,sys.argv[1:4]);pkg_sha=sys.argv[4]
source='23185f299ce61b8e373ebf5115b461ad2aa01226';run=39220053878
assets=p.parents[2]/'dist'/f'github-candidate-v4.3.23-{run}'
files={'SHA256SUMS.txt','Wattson-v4.3.23-macos-universal.pkg','Wattson-v4.3.23-macos-universal.dmg','Wattson-v4.3.23-release-info.txt'}
proofs=list(p.glob(f'artifact-{run}-review.*/artifact-proof.json'));assert len(proofs)==1,'Expected one reviewed candidate proof'
proof=json.loads(proofs[0].read_text());assert proof['candidate_checks_passed'] is True and proof['run_id']==run and proof['source_sha']==source
assert Path(proof['retained_exact_assets'])==assets
for name,sha in proof['evidence_sha256'].items():assert hashlib.sha256((proofs[0].parent/name).read_bytes()).hexdigest()==sha
assert assets.is_dir() and not assets.is_symlink() and {x.name for x in assets.iterdir()}==files
hashes={}
for name in files:
 path=assets/name;assert path.is_file() and not path.is_symlink();hashes[name]=hashlib.sha256(path.read_bytes()).hexdigest()
manifest={}
for line in (assets/'SHA256SUMS.txt').read_text().splitlines():
 m=re.fullmatch(r'([0-9a-f]{64})  (.+)',line);assert m and m[2] in files-{'SHA256SUMS.txt'} and m[2] not in manifest
 manifest[m[2]]=m[1]
assert set(manifest)==files-{'SHA256SUMS.txt'} and all(hashes[n]==sha for n,sha in manifest.items())
assert manifest['Wattson-v4.3.23-macos-universal.pkg']==pkg_sha
saved=json.loads((p/'release-created.json').read_text());live=json.loads((scratch/'live-release.json').read_text())
for release in (saved,live):
 assert release['tag_name']=='v4.3.23' and release['draft'] is False and release['prerelease'] is False
 assert release['html_url']=='https://github.com/laleoarrow/battery-monitor/releases/tag/v4.3.23'
 for name,sha in hashes.items():
  matches=[x for x in release['assets'] if x['name']==name];assert len(matches)==1
  assert matches[0]['digest']=='sha256:'+sha and matches[0]['size']==(assets/name).stat().st_size
assert saved['id']==live['id']
tag=json.loads((scratch/'tag-object.json').read_text());assert tag['tag']=='v4.3.23' and tag['object']['type']=='commit' and tag['object']['sha']==source
assert json.loads((scratch/'main-ref.json').read_text())['object']['sha']==source
(record/'tap-preflight.json').write_text(json.dumps({'version':'4.3.23','source_sha':source,'candidate_run_id':run,'candidate_proof':str(proofs[0]),'release_id':live['id'],'all_four_public_api_digests_match_candidate':True,'public_pkg_sha256':pkg_sha,'candidate_file_sha256':hashes},indent=2)+'\n')
PY
checkout="$scratch/tap"
wattson_run_timeout 120 git clone --single-branch --branch main git@github.com:laleoarrow/homebrew-tap.git "$checkout"
wattson_run_timeout 30 git -C "$checkout" ls-remote origin refs/heads/main > "$record/tap-remote-before-sync.txt"
base="$(git -C "$checkout" rev-parse HEAD)"
[[ "$(awk '{print $1}' "$record/tap-remote-before-sync.txt")" == "$base" ]]
printf '%s\n' "$base" > "$record/tap-base-commit.txt"
[[ -z "$(git -C "$checkout" status --porcelain)" ]]
[[ -f "$checkout/Casks/wattson.rb" && ! -L "$checkout/Casks" && ! -L "$checkout/Casks/wattson.rb" ]]
cp "$checkout/Casks/wattson.rb" "$record/tap-cask-before.rb"
/usr/bin/python3 - "$checkout/Casks/wattson.rb" "$PKG_SHA" <<'PY'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1]);old=p.read_text()
assert old.count('  version "4.3.22"\n')==1,'Expected the previous public cask version'
new,n=re.subn(r'^  version "4[.]3[.]22"$','  version "4.3.23"',old,flags=re.M);assert n==1
new,n=re.subn(r'^  sha256 "[0-9a-f]{64}"$','  sha256 "'+sys.argv[2]+'"',new,flags=re.M);assert n==1
assert len(old.splitlines())==len(new.splitlines()) and sum(a!=b for a,b in zip(old.splitlines(),new.splitlines()))==2
p.write_text(new)
PY
cp "$checkout/Casks/wattson.rb" "$record/tap-cask-after.rb"
wattson_run_timeout 30 ruby -c "$checkout/Casks/wattson.rb" > "$record/tap-ruby-syntax.log"
git -C "$checkout" diff --check
[[ "$(git -C "$checkout" status --porcelain)" == ' M Casks/wattson.rb' ]]
[[ "$(git -C "$checkout" diff --numstat)" == $'2\t2\tCasks/wattson.rb' ]]
git -C "$checkout" diff -- Casks/wattson.rb > "$record/tap-change.diff"
git -C "$checkout" add -- Casks/wattson.rb
wattson_run_timeout 60 git -C "$checkout" commit -m 'wattson 4.3.23' > "$record/tap-commit.log"
tap_commit="$(git -C "$checkout" rev-parse HEAD)"
[[ "$(git -C "$checkout" rev-parse HEAD^)" == "$base" ]]
[[ "$(git -C "$checkout" diff-tree --no-commit-id --name-only -r HEAD)" == 'Casks/wattson.rb' ]]
[[ "$(git -C "$checkout" diff-tree --no-commit-id --numstat -r HEAD)" == $'2\t2\tCasks/wattson.rb' ]]
[[ -z "$(git -C "$checkout" status --porcelain)" ]]
printf '%s\n' "$tap_commit" > "$record/tap-commit.txt"
git -C "$checkout" ls-tree -r HEAD > "$record/tap-tree-after.txt"
wattson_run_timeout 120 git -C "$checkout" push origin HEAD:refs/heads/main > "$record/tap-push.log" 2>&1
wattson_run_timeout 30 git -C "$checkout" ls-remote origin refs/heads/main > "$record/tap-remote-after-sync.txt"
[[ "$(awk '{print $1}' "$record/tap-remote-after-sync.txt")" == "$tap_commit" ]]
printf 'TAP_SYNC_PUSHED %s\nEvidence: %s\n' "$tap_commit" "$record"
