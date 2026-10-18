#!/usr/bin/env python3
import hashlib,json,pathlib,sys,tarfile

root=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else pathlib.Path(__file__).resolve().parent
results=root/'guest-results'
if not results.exists(): results=root
tolerance=0.0001  # points, fixed before observing results; far below one display pixel.
def difference(a,b):
    if isinstance(a,(int,float)) and isinstance(b,(int,float)): return abs(a-b)
    if isinstance(a,list) and isinstance(b,list) and len(a)==len(b): return max([difference(x,y) for x,y in zip(a,b)]+[0])
    if isinstance(a,dict) and isinstance(b,dict) and a.keys()==b.keys(): return max([difference(a[k],b[k]) for k in a]+[0])
    return 0 if a==b else float('inf')
summary={'schema':1,'geometryTolerancePoints':tolerance,'versions':{},'isReplacementForOriginalNormalMotionGate':False}
for revision in ('baseline','candidate'):
    path=results/(revision+'.json')
    if path.exists(): raw=path.read_bytes()
    else:
        with tarfile.open(root/'continuous-loop-raw.tar.gz','r:gz') as archive:
            raw=archive.extractfile(revision+'.json').read()
    data=json.loads(raw)
    version={'rawSHA256':hashlib.sha256(raw).hexdigest(),'eventLoopRuns':data['eventLoopRuns'],'stopsDuringObservation':data['stopsDuringObservation'],'initialExactCGPathEquality':data['baselineCommittedBeforeUpdates'],'instances':{}}
    for name in ('normal','frozen'):
        records=[r for r in data['records'] if r['instance']==name]
        readings=[]
        for record in records:
            paths=[layer for layer in record['layers'] if layer['modelPath'] is not None]
            heads=[layer for layer in record['layers'] if layer['isHead']]
            assert len(heads)==1
            delta=max([difference(layer['modelPath'],layer['presentationPath']) for layer in paths]+[0])
            head=difference(heads[0]['modelPosition'],heads[0]['presentationPosition'])
            readings.append({'observation':record['observation'],'elapsed':record['elapsed'],'withinOneSecond':record['withinOneSecond'],'modelPaths':len(paths),'maxPathTargetDeltaPoints':delta if delta!=float('inf') else None,'headTargetDeltaPoints':head if head!=float('inf') else None,'allPresentationGeometryAtTarget':delta<=tolerance and head<=tolerance,'animationKeys':[key for layer in record['layers'] for key in layer['keys']]})
        later=[r for r in records if r['observation'].startswith('scheduled-') and r['withinOneSecond']]
        stable=False; variation=None
        if len(later)>=2:
            old,new=later[-2:]
            changes=[]
            for a,b in zip(old['layers'],new['layers']):
                if a['modelPath'] is not None: changes.append(difference(a['presentationPath'],b['presentationPath']))
                if a['isHead']: changes.append(difference(a['presentationPosition'],b['presentationPosition']))
            variation=max(changes+[0]);stable=variation<=tolerance
        version['instances'][name]={'observations':readings,'inDeadlineLaterObservations':len(later),'lastTwoPresentedGeometryStable':stable,'lastTwoMaxPresentedDeltaPoints':variation if variation!=float('inf') else None}
    summary['versions'][revision]=version
summary['limitations']='Single narrow matched-tail input pair with fresh instances and an uninterrupted AppKit loop. Does not recreate all preceding full-suite state or contracted-axis sequence; host was reported unlocked before this later run. Clean results cannot by themselves establish that loop boundaries caused prior failures. Original failures and gate status remain unchanged.'
(root/'continuous-loop-summary.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n')
print(json.dumps(summary,indent=2))
