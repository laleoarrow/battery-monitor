#!/bin/bash
# Prepare/commit/push only the public, checksum-bound Wattson cask when invoked.
set -euo pipefail
umask 077
if [[ "$#" != 3 || ! "$1" =~ ^[0-9a-f]{64}$ || ! "$2" =~ ^[0-9a-f]{40}$ || ! "$3" =~ ^[1-9][0-9]+$ ]]; then
    echo 'usage: /bin/bash tap-sync.sh VERIFIED-PKG-SHA256 SOURCE-SHA CANDIDATE-RUN-ID' >&2
    exit 2
fi
PKG_SHA="$1"
SOURCE_SHA="$2"
CANDIDATE_RUN="$3"
readonly PKG_SHA SOURCE_SHA CANDIDATE_RUN
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
evidence="$repo/design/release-v5.0.2/publication"
source "$repo/scripts/lib/local_cleanup.sh"
wattson_cleanup_init
mkdir -p "$repo/.build/tap-sync-v5.0.2.noindex"
scratch="$(mktemp -d "$repo/.build/tap-sync-v5.0.2.noindex/work.XXXXXX")"
wattson_cleanup_add_dir "$scratch"
record="$(mktemp -d "$evidence/tap-sync-review.XXXXXX")"
mkdir "$scratch/tmp"
export TMPDIR="$scratch/tmp"
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONOPTIMIZE
export GIT_TERMINAL_PROMPT=0
printf '%s\n' "$scratch" > "$record/tap-workspace.txt"
[[ -f "$evidence/release-created.json" && ! -L "$evidence/release-created.json" && -f "$evidence/artifact-public-provenance.json" && ! -L "$evidence/artifact-public-provenance.json" ]] || {
    echo 'Verified release-created.json and public provenance are required before tap synchronization.' >&2; exit 1;
}
wattson_run_timeout 45 gh api repos/laleoarrow/battery-monitor/releases/tags/v5.0.2 > "$scratch/live-release.json"
wattson_run_timeout 45 gh api repos/laleoarrow/battery-monitor/git/ref/tags/v5.0.2 > "$scratch/tag-ref.json"
TAG_OBJECT="$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["object"]["type"]=="tag"; print(d["object"]["sha"])' "$scratch/tag-ref.json")"
[[ "$TAG_OBJECT" =~ ^[0-9a-f]{40}$ ]]
wattson_run_timeout 45 gh api "repos/laleoarrow/battery-monitor/git/tags/$TAG_OBJECT" > "$scratch/tag-object.json"
wattson_run_timeout 45 gh api repos/laleoarrow/battery-monitor/git/ref/heads/main > "$scratch/main-ref.json"
/usr/bin/python3 - "$evidence" "$scratch" "$record" "$PKG_SHA" "$SOURCE_SHA" "$CANDIDATE_RUN" <<'PY'
import hashlib,json,re,sys
from pathlib import Path
p,scratch,record=map(Path,sys.argv[1:4]);pkg_sha=sys.argv[4]
source=sys.argv[5];run=int(sys.argv[6])
assets=p.parents[2]/'dist'/f'github-candidate-v5.0.2-{run}'
files={'SHA256SUMS.txt','Wattson-v5.0.2-macos-universal.pkg','Wattson-v5.0.2-macos-universal.dmg','Wattson-v5.0.2-release-info.txt'}
proofs=list(p.glob(f'artifact-{run}-review.*/artifact-proof.json'));assert len(proofs)==1,'Expected one reviewed candidate proof'
proof=json.loads(proofs[0].read_text());assert proof['candidate_checks_passed'] is True and proof['run_id']==run and proof['source_sha']==source and proof['version']=='5.0.2'
assert Path(proof['retained_exact_assets'])==assets
for name,sha in proof['evidence_sha256'].items():assert hashlib.sha256((proofs[0].parent/name).read_bytes()).hexdigest()==sha
assert not Path((proofs[0].parent/'artifact-workspace.txt').read_text().strip()).exists(),'Candidate cleanup is incomplete'
expected=json.loads((proofs[0].parent/'artifact-download.json').read_text())['files'];assert set(expected)==files
assert assets.is_dir() and not assets.is_symlink() and {x.name for x in assets.iterdir()}==files
hashes={}
for name in files:
 path=assets/name;assert path.is_file() and not path.is_symlink();hashes[name]=hashlib.sha256(path.read_bytes()).hexdigest()
 assert hashes[name]==expected[name]['sha256'] and path.stat().st_size==expected[name]['bytes'],'Accepted candidate bytes changed'
manifest={}
for line in (assets/'SHA256SUMS.txt').read_text().splitlines():
 m=re.fullmatch(r'([0-9a-f]{64})  (.+)',line);assert m and m[2] in files-{'SHA256SUMS.txt'} and m[2] not in manifest
 manifest[m[2]]=m[1]
assert set(manifest)==files-{'SHA256SUMS.txt'} and all(hashes[n]==sha for n,sha in manifest.items())
assert manifest['Wattson-v5.0.2-macos-universal.pkg']==pkg_sha
provenance_path=p/'artifact-public-provenance.json';public=json.loads(provenance_path.read_text())
public_assets=p.parents[2]/'dist/public-v5.0.2-verify'
assert public['version']=='5.0.2' and public['sourceCommit']==source and public['candidateRunID']==run
assert public['packageSHA256']==pkg_sha and public['publicAssetsMatchCandidate'] is True and public['packageVerified'] is True
assert public['anonymousDownload'] is True and public['strictThreeEntryManifest'] is True
assert Path(public['candidateProof'])==proofs[0] and public['candidateProofSHA256']==hashlib.sha256(proofs[0].read_bytes()).hexdigest()
assert Path(public['publicAssetDirectory'])==public_assets and public_assets.is_dir() and not public_assets.is_symlink()
assert set(public['files'])==files and {x.name for x in public_assets.iterdir()}==files
assert not Path((p/'artifact-public-workspace.txt').read_text().strip()).exists(),'Public verification cleanup is incomplete'
for name,sha in hashes.items():
 path=public_assets/name;item=public['files'][name]
 assert path.is_file() and not path.is_symlink() and item['cmpToCandidate'] is True
 assert hashlib.sha256(path.read_bytes()).hexdigest()==sha==item['sha256'] and path.stat().st_size==item['bytes']==expected[name]['bytes']
saved=json.loads((p/'release-created.json').read_text());live=json.loads((scratch/'live-release.json').read_text())
for release in (saved,live):
 assert release['tag_name']=='v5.0.2' and release['draft'] is False and release['prerelease'] is False
 assert release['html_url']=='https://github.com/laleoarrow/battery-monitor/releases/tag/v5.0.2'
 for name,sha in hashes.items():
  matches=[x for x in release['assets'] if x['name']==name];assert len(matches)==1
  assert matches[0]['digest']=='sha256:'+sha and matches[0]['size']==(assets/name).stat().st_size
assert saved['id']==live['id']==public['releaseID']
tag=json.loads((scratch/'tag-object.json').read_text());assert tag['tag']=='v5.0.2' and tag['object']['type']=='commit' and tag['object']['sha']==source
assert json.loads((scratch/'main-ref.json').read_text())['object']['sha']==source
(record/'tap-preflight.json').write_text(json.dumps({'version':'5.0.2','source_sha':source,'candidate_run_id':run,'candidate_proof':str(proofs[0]),'release_id':live['id'],'all_four_public_api_digests_match_candidate':True,'public_pkg_sha256':pkg_sha,'candidate_file_sha256':hashes,'public_provenance_sha256':hashlib.sha256(provenance_path.read_bytes()).hexdigest(),'public_bytes_match_candidate':True},indent=2)+'\n')
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
assert old.count('  version "5.0.1"\n')==1,'Expected the previous public cask version'
new,n=re.subn(r'^  version "5[.]0[.]1"$','  version "5.0.2"',old,flags=re.M);assert n==1
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
wattson_run_timeout 60 git -C "$checkout" commit -m 'wattson 5.0.2' > "$record/tap-commit.log"
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
