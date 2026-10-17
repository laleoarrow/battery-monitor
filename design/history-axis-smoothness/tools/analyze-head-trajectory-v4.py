"""Independent dense evaluation of native animation payloads, not FPS."""
import bisect, json, math, sys
from pathlib import Path

root = Path(sys.argv[1])
data = json.loads((root/'motion/controlled/axis-motion.json').read_text())
def curves(meta):
    out = []; start = None
    for kind, points in zip(meta['commands'], meta['points']):
        if kind == 0: start = points[0]
        elif kind == 3: out.append([start] + points); start = points[-1]
    return out
def cubic(c, t):
    u=1-t
    return [u*u*u*c[0][k]+3*u*u*t*c[1][k]+3*u*t*t*c[2][k]+t*t*t*c[3][k] for k in range(2)]
results=[]
for event in data['events']:
    if event['event'] != 'after-retarget-commit': continue
    animations={a['key']:a for l in event['layers'] for a in l['animations']}
    stroke,head=animations['history.stroke'],animations['history.head']
    a,b=curves(stroke['fromPath']),curves(stroke['toPath'])
    positions=head['positionValues']
    times=head.get('positionKeyTimes') or [i/(len(positions)-1) for i in range(len(positions))]
    assert len(times)==len(positions) and times[0]==0 and times[-1]==1
    assert all(x<y for x,y in zip(times,times[1:]))
    gradient=next(l for l in event['layers'] if l['kind']=='CAGradientLayer')
    top=gradient['effectiveBandStart'][1]
    max_error=0; at=None; samples=0
    for index in range(1,4096):
        q=index/4096
        j=min(bisect.bisect_right(times,q)-1,len(times)-2)
        f=(q-times[j])/(times[j+1]-times[j])
        dot=[positions[j][k]+(positions[j+1][k]-positions[j][k])*f for k in range(2)]
        dot[1]-=top
        found=None
        for left,right in zip(a,b):
            start=left[0][0]*(1-q)+right[0][0]*q
            end=left[-1][0]*(1-q)+right[-1][0]*q
            if start-1e-6<=dot[0]<=end+1e-6:
                found=[[p[k]*(1-q)+r[k]*q for k in range(2)] for p,r in zip(left,right)]
                break
        assert found is not None
        lo,hi=0.0,1.0
        for _ in range(35):
            mid=(lo+hi)/2
            if cubic(found,mid)[0]<dot[0]:lo=mid
            else:hi=mid
        reference=cubic(found,(lo+hi)/2)
        error=abs(reference[1]-dot[1]);samples+=1
        if error>max_error:max_error=error;at=q
    results.append({'phase':event['phase'],'keyframes':len(positions),'denseProgressSamples':samples,
                    'maximumDeviationPoints':max_error,'progressAtMaximum':at})
result={'passed':len(results)==10 and all(r['maximumDeviationPoints']<=.15 for r in results),
        'measurement':'Independent interpolation of actual native from/to path controls, position values and keyTimes. Continuous geometry lookup uses all four points and bisection in X. Not composited frames or FPS.',
        'results':results}
(root/'head-trajectory-analysis-v4.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
raise SystemExit(0 if result['passed'] else 1)
