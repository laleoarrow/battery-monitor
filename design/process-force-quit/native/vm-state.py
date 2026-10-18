#!/usr/bin/env python3
import json, os, pathlib, sys
name=os.environ.get('WATTSON_QA_VM_NAME', 'Wattson-Process-Force-Quit-20261018')
mode=sys.argv[1]
before=json.loads(pathlib.Path(sys.argv[2]).read_text())
vms={v['Name']:v for v in before}
if mode=='preflight':
    if name in vms: raise RuntimeError('Owned clone name already exists; refuse reuse')
    if any(vms[n]['State']!='stopped' for n in ('macOS-TestLab','macOS-TestLab-Base')):
        raise RuntimeError('Required TestLab/Base state changed; no mutation performed')
elif mode=='state':
    print(vms[name]['State'] if name in vms else 'missing')
elif mode=='after':
    after=json.loads(pathlib.Path(sys.argv[3]).read_text())
    current={v['Name']:v for v in after}
    if name in current or not set(vms).issubset(current): raise RuntimeError('Owned clone deletion or existing VM inventory check failed')
    checks={n:v['State']==current[n]['State'] and v['Running']==current[n]['Running'] for n,v in vms.items()}
    if not all(checks.values()): raise RuntimeError('Another VM state changed; never repair it automatically')
    print(json.dumps({'ownedVM':name,'ownedCloneRemoved':True,'otherVMStatesPreserved':checks,
                      'additionalUnrelatedVMsPreserved':sorted(set(current)-set(vms))},sort_keys=True))
else: raise RuntimeError('Unknown mode')
