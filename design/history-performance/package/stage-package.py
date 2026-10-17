from pathlib import Path
import hashlib, json, os, shutil, signal, subprocess, sys, tarfile, tempfile, time

# This bootstrap is passed as exact bytes in tart exec's Python -c argument.
manifest = json.loads(sys.argv[1])
validation_label = manifest.get('validationLabel', 'unlabeled')
assert validation_label and all(c in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in validation_label)
candidate_name, candidate_sha, version, previous_name, previous_sha, previous_version, commit = sys.argv[2:]
assert os.getuid() != 0
assert subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.model'], text=True).strip().startswith('VirtualMac')
assert subprocess.check_output(['/usr/bin/uname', '-m'], text=True).strip() == 'arm64'
assert len(candidate_sha) == len(previous_sha) == 64 and len(commit) == 40
assert all(c in '0123456789abcdef' for c in candidate_sha + previous_sha + commit)
assert Path(candidate_name).name == candidate_name and Path(previous_name).name == previous_name
share = Path('/Volumes/My Shared Files/performance/package-validation')
repo_dist = Path('/Volumes/My Shared Files/repo/dist')
project = Path.home() / 'Project/Wattson-HistoryPerf-QA'
assert project.is_dir() and share.is_dir() and repo_dist.is_dir()
root = project / '.build/package-staged.noindex'
root.mkdir(parents=True, exist_ok=True)
run = Path(tempfile.mkdtemp(prefix='run.', dir=root))
results = run / 'results'
child = None
code = None
bootstrap_error = None
signals = [signal.SIGHUP, signal.SIGINT, signal.SIGTERM]

def interrupted(number, frame):
    raise SystemExit(128 + number)

for number in signals:
    signal.signal(number, interrupted)
try:
    archive = run / 'tools.tar.gz'
    shutil.copyfile(share / manifest['archive'], archive)
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == manifest['archiveSHA256']
    tools = run / 'tools'
    with tarfile.open(archive, 'r:gz') as stream:
        assert set(stream.getnames()) == set(manifest['files'])
        for member in stream.getmembers():
            assert member.isfile() and member.name in manifest['files']
            target = tools / member.name
            assert '..' not in Path(member.name).parts and not Path(member.name).is_absolute()
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(stream.extractfile(member).read())
    actual = {name: hashlib.sha256((tools / name).read_bytes()).hexdigest() for name in manifest['files']}
    assert actual == manifest['files']
    packages = []
    for name, expected in [(candidate_name, candidate_sha), (previous_name, previous_sha)]:
        target = run / name
        shutil.copyfile(repo_dist / name, target)
        assert hashlib.sha256(target.read_bytes()).hexdigest() == expected
        packages.append(target)
    provenance = {'validationLabel': validation_label, 'preliminary': validation_label.startswith('preliminary-'), 'sourceCommit': commit, 'candidateVersion': version, 'candidatePackageSHA256': candidate_sha, 'previousVersion': previous_version, 'previousPackageSHA256': previous_sha, 'toolsArchiveSHA256': manifest['archiveSHA256'], 'hostBootstrapSHA256': manifest['hostBootstrapSHA256'], 'guestLocalToolSHA256': actual, 'allHashesVerifiedBeforeExecution': True, 'guestLocalRoot': str(run), 'productionAppResidencyApplicable': False, 'boundary': 'VirtualMac has no AppleSmartBattery; physical host readiness is a separate root-owned gate.'}
    (run / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    blocked = signal.pthread_sigmask(signal.SIG_BLOCK, signals)
    try:
        with (run / 'runner.log').open('wb') as log:
            child = subprocess.Popen(['/usr/bin/python3', str(tools / 'lib/run_owned.py'), '--grace', '65', '--timeout', '1800', '--', '/bin/bash', str(tools / 'run-package-qa.sh'), str(packages[0]), candidate_sha, version, str(packages[1]), previous_sha, previous_version, str(results), commit], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, blocked)
    code = child.wait(timeout=1900)
except BaseException as error:
    bootstrap_error = repr(error)
    if code is None:
        code = error.code if isinstance(error, SystemExit) and isinstance(error.code, int) else 1
finally:
    if code is None:
        code = 1
    for number in signals:
        signal.signal(number, signal.SIG_IGN)
    try:
        if child is not None and child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=90)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=10)
        results.mkdir(exist_ok=True)
        for name in ['provenance.json', 'runner.log']:
            if (run / name).is_file():
                shutil.copyfile(run / name, results / name)
        if bootstrap_error is not None:
            (results / 'bootstrap-error.txt').write_text(bootstrap_error + '\n')
        (results / 'stage-exit-code.txt').write_text(str(code) + '\n')
        files = {str(p.relative_to(results)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(results.rglob('*')) if p.is_file()}
        (results / 'SHA256.json').write_text(json.dumps(files, indent=2) + '\n')
        packed = run / 'package-results.tar.gz'
        with tarfile.open(packed, 'w:gz') as stream:
            for path in sorted(results.rglob('*')):
                if path.is_file():
                    stream.add(path, arcname='results/' + str(path.relative_to(results)), recursive=False)
        digest = hashlib.sha256(packed.read_bytes()).hexdigest()
        output = share / f'package-results-{validation_label}-{commit[:12]}-{digest}.tar.gz'
        assert not output.exists()
        shutil.copyfile(packed, output)
        assert hashlib.sha256(output.read_bytes()).hexdigest() == digest
        print(json.dumps({'exitCode': code, 'archive': output.name, 'archiveSHA256': digest, 'fileCount': len(files) + 1, 'guestLocalToolsAndPackagesVerified': True, 'archivedOnFailure': True}), flush=True)
    except BaseException as error:
        print(json.dumps({'exportOrChildCleanupError': repr(error), 'originalExitCode': code}), file=sys.stderr, flush=True)
        if code == 0:
            code = 1
    finally:
        try:
            shutil.rmtree(run)
        except BaseException as error:
            print(json.dumps({'guestStagingCleanupError': repr(error), 'originalExitCode': code}), file=sys.stderr, flush=True)
            if code == 0:
                code = 1
raise SystemExit(code)
