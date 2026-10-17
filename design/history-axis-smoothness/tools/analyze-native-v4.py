import json, math, sys
from pathlib import Path

root = Path(sys.argv[1])
gallery_root = Path(sys.argv[2]) if len(sys.argv) > 2 else root
scalar = json.loads((root/'motion/scalar/axis-motion.json').read_text())
controlled = json.loads((root/'motion/controlled/axis-motion.json').read_text())
recording = json.loads((root/'motion/frames/axis-motion.json').read_text())
checks = []
def check(name, ok, detail=None):
    checks.append({'name': name, 'passed': bool(ok), 'detail': detail})
def animations(event):
    return [a for layer in event.get('layers', []) for a in layer.get('animations', [])]
def gradient(event):
    return next((l for l in event['layers'] if l['kind'] == 'CAGradientLayer'), None)
def keyed_points(event, key, identity):
    return {p[identity]: (p['x'], p['y']) for p in event.get(key, [])}
def max_distance(a, b):
    if not a or set(a) != set(b): return math.inf
    return max(math.dist(a[k], b[k]) for k in a)
def curves(meta):
    result = []; start = None
    for kind, points in zip(meta['commands'], meta['points']):
        if kind == 0: start = points[0]
        elif kind == 3:
            result.append([start] + points); start = points[-1]
        elif kind == 1: start = points[0]
    return result
def shape(event, key):
    return next((a for a in animations(event) if a['key'] == key), None)

path_count = 0
for data in (scalar, controlled):
    for event in data['events']:
        stroke, fill = shape(event, 'history.stroke'), shape(event, 'history.fill')
        if not stroke: continue
        path_count += 1
        good = bool(fill)
        for animation in (stroke, fill):
            good = good and animation is not None and animation['animationClass'] in ('CABasicAnimation', 'CAKeyframeAnimation')
            if not good: break
            a, b = animation.get('fromPath'), animation.get('toPath')
            good = bool(a and b and a['finite'] and b['finite'] and a['commands'] == b['commands'])
        if good:
            good = (curves(stroke['fromPath']) == curves(fill['fromPath'])
                    and curves(stroke['toPath']) == curves(fill['toPath'])
                    and abs(stroke['beginTime'] - fill['beginTime']) < 1e-6
                    and stroke['duration'] == fill['duration'])
        if good and stroke['animationClass'] == 'CAKeyframeAnimation':
            good = stroke.get('pathFrameCount') == fill.get('pathFrameCount') == 9
            good = good and stroke.get('pathTopologyMatches') and fill.get('pathTopologyMatches')
            good = good and all(curves(x) == curves(y) for x,y in zip(stroke['pathFrames'],fill['pathFrames']))
        check('synchronized finite native paths '+event['phase']+' '+event['event'], good)
check('native path coverage', path_count >= 50, path_count)

retargets = []
for phase in sorted({e['phase'] for e in controlled['events']}):
    events = [e for e in controlled['events'] if e['phase'] == phase]
    before = next(e for e in events if e['event'] == 'before-retarget')
    after = next(e for e in events if e['event'] == 'after-retarget-commit')
    end = next(e for e in events if e['event'] == 'after-settle')
    raw = max_distance(keyed_points(before, 'projectedRetainedSamples', 'sampledAt'),
                       keyed_points(after, 'projectedRetainedSamples', 'sampledAt'))
    interior = max_distance(keyed_points(before, 'interiorAnchors', 'sampledAtMidpoint'),
                            keyed_points(after, 'interiorAnchors', 'sampledAtMidpoint'))
    head = math.dist(before['headStroke']['head'], after['headStroke']['head'])
    a, b = gradient(before), gradient(after)
    band = max(math.dist(a[k], b[k]) for k in ('effectiveBandStart', 'effectiveBandEnd'))
    alpha = abs(a['retainedSampleAlphaEstimate'] - b['retainedSampleAlphaEstimate'])
    retargets.append({'phase': phase, 'rawAnchorJumpPoints': raw, 'interiorJumpPoints': interior,
                     'headJumpPoints': head, 'gradientBandJumpPoints': band, 'alphaEstimateJump': alpha})
    check('controlled C0 '+phase, max(raw, interior, head, band) <= .001 and alpha <= .00001, retargets[-1])
    # Include the newest retained interval, which was absent from the original
    # three-point tracking set, and compare every control in all common pairs.
    updates = [e for e in events if e['event'] == 'update' and e['hasChartAnimation']]
    old_update,new_update = updates[0],updates[-1]
    old_line = next(l for l in before['layers'] if any(a['key']=='history.stroke' for a in l['animations']))
    new_line = next(l for l in after['layers'] if any(a['key']=='history.stroke' for a in l['animations']))
    old_actual,new_actual = curves(old_line['actualPath']),curves(new_line['actualPath'])
    old_model,new_model = curves(shape(before,'history.stroke')['toPath']),curves(shape(after,'history.stroke')['toPath'])
    width=gradient(after)['effectiveBandEnd'][0]*2
    common=sorted(set(old_update['times']) & set(new_update['times']))
    jumps=[]
    for left,right in zip(common,common[1:]):
        def index(model,reference):
            x0=width*(1-(reference-left)/120);x1=width*(1-(reference-right)/120)
            return next((i for i,c in enumerate(model) if abs(c[0][0]-x0)<1e-5 and abs(c[-1][0]-x1)<1e-5),None)
        i,j=index(old_model,old_update['times'][-1]),index(new_model,new_update['times'][-1])
        if i is not None and j is not None:
            jumps.extend(math.dist(p,q) for p,q in zip(old_actual[i],new_actual[j]))
    check('all retained controls C0 '+phase, len(jumps)>=200 and max(jumps)<=.001, {'points':len(jumps),'maximumJump':max(jumps) if jumps else None})
    # A paused parent keeps animation bookkeeping registered after its local
    # clock jumps past the end. Test convergence here; real-time removal is
    # checked independently in every natural phase and the UI harness.
    update = [e for e in events if e['event'] == 'update'][-1]
    ceiling, reference = update['ceiling'], update['times'][-1]
    band_end = gradient(end)
    width = band_end['effectiveBandEnd'][0] * 2
    top = band_end['effectiveBandStart'][1]
    height = band_end['effectiveBandEnd'][1] - top
    expected = {p['sampledAt']: (width * (1-(reference-p['sampledAt'])/120),
                 top+height*(1-p['watts']/ceiling)) for p in end['projectedRetainedSamples']}
    endpoint_error = max_distance(keyed_points(end,'projectedRetainedSamples','sampledAt'), expected)
    expected_head = (width,top+height*(1-update['values'][-1]/ceiling))
    endpoint_error = max(endpoint_error,math.dist(end['headStroke']['head'],expected_head))
    check('controlled converges to target '+phase, endpoint_error <= .001, endpoint_error)
check('controlled transition coverage', len(retargets) == 10, len(retargets))

metrics = []
for data in (scalar, controlled):
    rows = data['samples'] + [e for e in data['events'] if e['event'] not in ('update', 'before-retarget')]
    for event in rows:
        metric = event.get('headStroke', {})
        if metric:
            metrics.append(metric)
check('native non-knot head/curve and fill/curve coverage', len(metrics) > 200, len(metrics))
max_head = max(m['deviationPoints'] for m in metrics)
max_fill = max(m['fillStrokeMaxDeviationPoints'] for m in metrics)
check('head stays close between keyframes', max_head <= .15, max_head)
check('actual presentation fill matches stroke', all(0 <= m['fillStrokeMaxDeviationPoints'] <= .01 for m in metrics), max_fill)
check('native X remains monotone', all(m['minimumXDerivativePoints'] >= -1e-7 for m in metrics), min(m['minimumXDerivativePoints'] for m in metrics))
check('native cubics do not overshoot adjacent endpoints', all(m['maximumYOvershootPoints'] <= .001 for m in metrics), max(m['maximumYOvershootPoints'] for m in metrics))
check('physical stroke and endpoint size', all(abs(m['presentationLineWidth'] - 1.6) < 1e-6
    and max(abs(a-b) for a,b in zip(m['presentationLineTransform'], [1,1,0,0])) < 1e-6
    and max(abs(v - 5.2) for v in m['headBounds']) < 1e-6 for m in metrics))
for phase in sorted({s['phase'] for s in scalar['samples']}):
    late = [s for s in scalar['samples'] if s['phase'] == phase and s['elapsed'] >= .8]
    check('natural settles '+phase, bool(late) and all(not s['hasChartAnimation'] for s in late))
for event in scalar['events']:
    if event['event'] == 'cancel': check('cancel immediately '+event['phase'], not event['hasChartAnimation'])

natural = []
for before in [e for e in scalar['events'] if e['event'] == 'before-retarget']:
    phase = before['phase']
    updates = [e for e in scalar['events'] if e['phase'] == phase and e['event'] == 'update' and e['hasChartAnimation']]
    initial = shape(updates[0], 'history.stroke')
    a, b, p = initial['fromPath'], initial['toPath'], before['capturedPresentationPath']
    ratios = []
    if a['commands'] == b['commands'] == p['commands']:
        for left,right,shown in zip(a['points'],b['points'],p['points']):
            if left and right and shown:
                for i in range(2):
                    delta=right[-1][i]-left[-1][i]
                    if abs(delta) > 1: ratios.append((shown[-1][i]-left[-1][i])/delta)
    q = sorted(ratios)[len(ratios)//2] if ratios else None
    settled = phase == 'settled-axis-to-basic'
    hit = settled or (before['hasChartAnimation'] and q is not None and 0 < q < 1)
    natural.append({'phase':phase, 'triggerElapsedSeconds':before['elapsed'], 'visibleGeometryProgress':q,
                    'activeBeforeRetarget':before['hasChartAnimation'], 'hitActiveWindow':hit})
    check('natural retarget window '+phase, hit, natural[-1])

frames = recording['frames']
check('actual WindowServer frames', len(frames) >= 50 and len({f['phase'] for f in frames}) == 18, len(frames))
captures = {}
for state in ('charging','full','on-battery','mixed-supply','low-battery','low-power'):
    directory = gallery_root/'gallery'/state
    pngs = list(directory.glob('*.png'))
    captures[state] = [p.name for p in pngs]
    check('production light and dark '+state, (directory/'complete.json').is_file() and len(pngs) >= 2, captures[state])
report = {'passed':all(c['passed'] for c in checks), 'checks':checks, 'controlledRetargets':retargets,
          'naturalRetargets':natural, 'metricSampleCount':len(metrics), 'maxHeadDeviationPoints':max_head,
          'maxFillDeviationPoints':max_fill, 'actualRecordedFrameCount':len(frames), 'captures':captures,
          'limits':'Position continuity (C0), no claim of velocity continuity (C1), FPS, CPU-time or energy. Frame capture has its own timestamps and overhead.'}
(root/'native-analysis-v4.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ('checks','captures','controlledRetargets')},indent=2))
for c in checks:
    if not c['passed']: print('FAILED',json.dumps(c))
raise SystemExit(0 if report['passed'] else 1)
