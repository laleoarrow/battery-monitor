from pathlib import Path
import json, math, statistics, sys
p=Path(sys.argv[1]).resolve()
r=json.loads(p.read_text())
assert r['mode']=='scalar' and r['PNGWorkDuringScalarPass'] is False
names=list(dict.fromkeys(x['phase'] for x in r['samples']))
checks=[]; summaries={}
def check(name,value,detail=None):
 checks.append({'name':name,'passed':bool(value),'detail':detail})
def animations(record):
 return [(layer['path'],animation) for layer in record['layers'] for animation in layer['animations']]
def projection(record):
 points=record['projectedRetainedSamples']
 return points[1]['y'] if len(points)==3 else None
for name in names:
 rows=[x for x in r['samples'] if x['phase']==name]
 events=[x for x in r['events'] if x['phase']==name]
 ts=[x['elapsed'] for x in rows]
 gaps=[b-a for a,b in zip(ts,ts[1:])]
 active=[x['elapsed'] for x in rows if x.get('hasChartAnimation',bool(animations(x)))]
 before=next(x for x in events if x['event']=='before-update')
 before_y=projection(before)
 ys=[projection(x) for x in rows]
 finite=before_y is not None and all(v is not None and math.isfinite(v) for v in ys)
 check(name+': real presentation samples',finite and len(rows)>=8,{'sampleCount':len(rows)})
 check(name+': monotonic sample timestamps',all(t>0 for t in gaps))
 check(name+': positive finite sampling intervals',gaps and all(math.isfinite(x) and x>0 for x in gaps),{'maxGapSeconds':max(gaps) if gaps else None})
 check(name+': animation observed',bool(active))
 check(name+': animation completed',not rows[-1].get('hasChartAnimation',bool(animations(rows[-1]))))
 budget=.9 if name.startswith('interrupted-scale') else (.4 if name=='ordinary-scroll' else .6)
 check(name+': short bounded native transition',active and max(active)<budget,{'lastActiveSeconds':max(active) if active else None,'allowedSeconds':budget})
 path_sets=[{a['key'] for _,a in animations(row) if a.get('keyPath')=='path'} for row in rows]
 check(name+': only matched stroke and fill path animations',all(not keys or keys <= {'history.stroke','history.fill'} for keys in path_sets))
 check(name+': path animation duration matches',all(len({a['duration'] for _,a in animations(row) if a.get('keyPath')=='path'})<=1 for row in rows))
 hs=[row.get('headStroke',{}) for row in rows]
 check(name+': actual head-to-stroke position available',all('deviationPoints' in x for x in hs))
 if all('deviationPoints' in x for x in hs):
  deviation=max(x['deviationPoints'] for x in hs)
  check(name+': endpoint stays on actual stroke',deviation<=.25,{'maxDeviationPoints':deviation})
  check(name+': stroke width remains 1.6 points',all(abs(x['presentationLineWidth']-1.6)<1e-6 for x in hs))
  check(name+': stroke transform remains identity',all(all(abs(a-b)<1e-6 for a,b in zip(x['presentationLineTransform'],[1,1,0,0])) for x in hs))
 heads=[l for row in rows for l in row['layers'] if abs(l['cornerRadius']-2.6)<.001]
 check(name+': constant endpoint diameter',heads and all(abs(l['bounds'][2]-5.2)<.001 and abs(l['bounds'][3]-5.2)<.001 for l in heads))
 if finite:
  series=[(0.0,before_y)]+list(zip(ts,ys))
  speeds=[abs(b[1]-a[1])/(b[0]-a[0]) for a,b in zip(series,series[1:])]
  if not name.startswith('cancel-'):
   check(name+': no retained-sample jump',max(speeds)<240,{'maximumYSpeedPointsPerSecond':max(speeds)})
  if name in ('ordinary-scroll','repeated-scroll'):
   check(name+': vertical coordinate remains fixed',max(ys+[before_y])-min(ys+[before_y])<.1)
  if name in ('scale-expansion','scale-contraction','departing-outlier-contraction','gradient-alpha-contraction'):
   direction=1 if name=='scale-expansion' else -1
   check(name+': physical y range changes',direction*(ys[-1]-before_y)>5)
   check(name+': intermediate y positions',len(set(round(y,2) for y in ys))>=3)
   check(name+': y progresses monotonically',all(direction*(b-a)>=-.15 for a,b in zip([before_y]+ys,ys)))
  if name.startswith('interrupted-scale'):
   check(name+': continuous retarget uses intermediate y positions',len(set(round(y,2) for y in ys))>=3)
   check(name+': retarget observed',any(e['event']=='before-retarget' for e in events))
  summaries[name]={'maxHeadToStrokeDeviationPoints':max([x.get('deviationPoints',0) for x in hs]),'samples':len(rows),'medianIntervalSeconds':statistics.median(gaps),'maximumIntervalSeconds':max(gaps),
                   'beforeY':before_y,'finalY':ys[-1],'distinctYPositions':len(set(round(y,2) for y in ys)),
                   'maximumYSpeedPointsPerSecond':max(speeds),'lastAnimationObservedSeconds':max(active) if active else None,
                   'animationKeys':sorted(set(a['key'] for row in rows for _,a in animations(row)))}
 if all(len(row.get('interiorAnchors',[]))==2 for row in rows) and len(before.get('interiorAnchors',[]))==2:
  by=before['interiorAnchors'][1]['y']; iy=[row['interiorAnchors'][1]['y'] for row in rows]
  check(name+': actual presentation path interior finite',all(math.isfinite(y) for y in iy))
  if not name.startswith('cancel-'):
   series=[(0.0,by)]+list(zip(ts,iy))
   speed=[abs(b[1]-a[1])/(b[0]-a[0]) for a,b in zip(series,series[1:])]
   check(name+': actual interval interior stays continuous',max(speed)<260,{'maxInteriorYSpeedPointsPerSecond':max(speed),'beforeY':by,'firstMeasuredY':iy[0],'firstMeasuredSeconds':ts[0]})
  summaries[name].update(actualPathInteriorBeforeY=by,actualPathInteriorFinalY=iy[-1])
 else:
  check(name+': actual presentation path interior available',False)
 gradient_before=next((l for l in before['layers'] if 'effectiveBandStart' in l),None)
 gradient_rows=[next((l for l in row['layers'] if 'effectiveBandStart' in l),None) for row in rows]
 if gradient_before and all(gradient_rows):
  starts=[l['effectiveBandStart'][1] for l in gradient_rows]; ends=[l['effectiveBandEnd'][1] for l in gradient_rows]
  alphas=[l.get('retainedSampleAlphaEstimate') for l in gradient_rows]
  check(name+': effective gradient band finite',all(math.isfinite(v) for v in starts+ends))
  band_drift=max(abs(v-gradient_before['effectiveBandStart'][1]) for v in starts)
  if not name.startswith('cancel-'):
   check(name+': effective gradient band stays continuous',band_drift<1.0,{'maxStartBandYDriftPoints':band_drift})
  summaries[name].update(effectiveGradientBandStartY=starts[-1],maxGradientBandDriftY=band_drift,
                         gradientAlphaBefore=gradient_before.get('retainedSampleAlphaEstimate'),gradientAlphaFinal=alphas[-1])
  if gradient_before.get('retainedSampleAlphaEstimate') is not None and all(a is not None and math.isfinite(a) for a in alphas):
   check(name+': alpha estimates remain bounded',all(0<=a<=1 for a in alphas))
   if not name.startswith('cancel-'):
    series=[(0,gradient_before['retainedSampleAlphaEstimate'])]+list(zip(ts,alphas))
    speeds=[abs(b[1]-a[1])/(b[0]-a[0]) for a,b in zip(series,series[1:])]
    check(name+': retained-sample gradient alpha stays continuous',max(speeds)<3,{'maximumAlphaChangePerSecond':max(speeds)})
 else:
  check(name+': gradient presentation band available',False)
 if name.startswith('cancel-'):
  cancelled=next(x for x in events if x['event']=='cancel')
  check(name+': cancellation removes animations immediately',not cancelled.get('hasChartAnimation',bool(animations(cancelled))))
  check(name+': cancellation leaves no later animations',not any(row.get('hasChartAnimation',bool(animations(row))) for row in rows if row['elapsed']>=cancelled['elapsed']))
report={'schema':1,'source':str(p),'sourceDescription':r['source'],'checks':checks,'checkCount':len(checks),'passed':sum(x['passed'] for x in checks),'allPassed':all(x['passed'] for x in checks),'summaries':summaries,
        'scope':'Measured real presentation-layer movement in disposable ARM GUI VM. Timer latency is harness timing, not a display FPS benchmark. Sparse PNG pass is independent visual evidence.'}
out=p.parent/'analysis.json'
assert not out.exists()
out.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'checkCount':len(checks),'passed':report['passed'],'allPassed':report['allPassed'],'failed':[x for x in checks if not x['passed']],'summaries':summaries},indent=2))
sys.exit(0 if report['allPassed'] else 1)
