#!/usr/bin/env python3
import hashlib, json, pathlib, sys, tarfile

mode = sys.argv[1]
if mode == 'archive':
    with tarfile.open(sys.argv[2], 'r:gz') as archive:
        values = {item.name: hashlib.sha256(archive.extractfile(item).read()).hexdigest()
                  for item in archive.getmembers() if item.isfile()}
    pathlib.Path(sys.argv[3]).write_text(''.join(f'{sha}  {name}\n' for name, sha in sorted(values.items())))
elif mode == 'verify':
    root = pathlib.Path(sys.argv[2])
    mismatches = []
    count = 0
    for line in pathlib.Path(sys.argv[3]).read_text().splitlines():
        sha, name = line.split(None, 1)
        target = root / name
        current = hashlib.sha256(target.read_bytes()).hexdigest() if target.is_file() else None
        count += 1
        if current != sha:
            mismatches.append({'file': name, 'expectedSHA256': sha, 'actualSHA256': current})
    report = {'schema': 1, 'allPassed': not mismatches, 'filesChecked': count, 'mismatches': mismatches}
    pathlib.Path(sys.argv[4]).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    sys.exit(0 if report['allPassed'] else 1)
else:
    raise ValueError('Unknown mode')
