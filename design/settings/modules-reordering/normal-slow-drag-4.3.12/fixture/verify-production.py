#!/usr/bin/env python3
"""Read-only frozen source identity before/after the owned fixture."""
import hashlib,json,sys
from pathlib import Path
root,out,mode=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]
assert mode in ('before','after')
files={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for group in ('Core','MenuBar','Popover') for f in sorted((root/group).glob('*.swift'))}
if mode=='before':
    (out/'source-production-before.json').write_text(json.dumps(files,sort_keys=True,indent=2)+'\n')
else:
    before=json.loads((out/'source-production-before.json').read_text())
    changed=sorted(k for k in set(before)|set(files) if before.get(k)!=files.get(k))
    report={'productionSourceUnchanged':not changed,'changedProductionPaths':changed,'productionFileCount':len(files),'afterFiles':files}
    (out/'source-production-after.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n')
    if changed:raise SystemExit(1)
