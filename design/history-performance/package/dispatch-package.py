from pathlib import Path
import hashlib, json, subprocess, sys

base = Path(__file__).resolve().parent
assert len(sys.argv) == 9
manifest_path = Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text())
assert manifest_path.parent.resolve() == base
archive = base / manifest['archive']
assert hashlib.sha256(archive.read_bytes()).hexdigest() == manifest['archiveSHA256']
assert {name: hashlib.sha256((base / name).read_bytes()).hexdigest() for name in manifest['hostBootstrapSHA256']} == manifest['hostBootstrapSHA256']
candidate, candidate_sha, version, previous, previous_sha, previous_version, commit = sys.argv[2:]
for name, expected in [(candidate, candidate_sha), (previous, previous_sha)]:
    path = Path(name)
    assert path.resolve().parent == base.parents[2] / 'dist'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected
code = (base / 'stage-package.py').read_text()
raise SystemExit(subprocess.call(['tart', 'exec', 'Wattson-HistoryPerf-20261016', '/usr/bin/python3', '-c', code, json.dumps(manifest), Path(candidate).name, candidate_sha, version, Path(previous).name, previous_sha, previous_version, commit]))
