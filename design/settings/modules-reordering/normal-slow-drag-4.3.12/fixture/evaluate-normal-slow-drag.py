#!/usr/bin/env python3
"""Evaluate frozen native callbacks; done/exit success is never a drag verdict."""
import argparse,hashlib,json,math
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('directory',type=Path);p.add_argument('--case',required=True);p.add_argument('--kind',choices=['drop','outside'],required=True);a=p.parse_args()
raw={n:(a.directory/n).read_bytes() for n in ('state.json','history.jsonl')}
s=json.loads(raw['state.json']);h=[json.loads(x) for x in raw['history.jsonl'].splitlines() if x.strip()];h=[x for x in h if x.get('case')==a.case]
checks={};missing=[]
def check(name,value):checks[name]=bool(value)
def need(value,reason):
 if not value:missing.append(reason)
def cleared(d):return d.get('available') is True and all(d.get(k) is True for k in ('draggedModuleIsNil','originalOrderIsEmpty','dragSessionIsNil'))
def rows(d):return {r['id']:r for r in d.get('rows',[])}
default=['flow','ring','lanes','history','runtime'];expected=default[1:]+default[:1] if a.kind=='drop' else default;n=1 if a.kind=='drop' else 0
need(s.get('case')==a.case and h,'Wrong final case or missing history')
base=next((x for x in h if x.get('savedOrder')==default and x.get('orderWrites')==0 and x.get('observedOwnWindowEventCount')==0 and x.get('lastCommand',{}).get('result')=='applied'),None)
need(base is not None,'Missing pre-input reset baseline');base=base or {}
obs=s.get('nativeDragObservation',{});need(obs.get('installed') is True,'Native source callbacks not observed')
check('originalIMPForwarded',obs.get('originalIMPInvokedExactlyOncePerObservedCallback') is True and obs.get('argumentsForwardedUnchanged') is True and obs.get('callbacksGeneratedByFixture') is False)
events=[e for e in s.get('nativeDragSessionEvents',[]) if e.get('case')==a.case]
phases=['willBegin.enter','willBegin.return','endedAt.enter','endedAt.return'];check('exactNativeCallbackSequence',[e.get('phase') for e in events]==phases)
need(all(any(e.get('phase')==phase for e in events) for phase in phases),'Missing genuine native willBegin/end pair')
check('sameNativeSession',len({e.get('sessionIdentity') for e in events})==1 and bool(events))
check('sameNativeSource',len({e.get('sourceIdentity') for e in events})==1 and bool(events))
check('noSyntheticCallback',all(e.get('syntheticCallback') is False for e in events))
begin=next((e for e in events if e.get('phase')=='willBegin.enter'),{})
end=next((e for e in events if e.get('phase')=='endedAt.return'),{})
check('realLeftButtonDownAtNativeStart',isinstance(begin.get('pressedMouseButtons'),int) and begin['pressedMouseButtons']&1==1)
held=None
try:
 held=end['monotonicUptime']-begin['monotonicUptime']
except (KeyError,TypeError):need(False,'Missing callback monotonic timestamps')
check('nativeSessionHeldOverOneSecond',held is not None and math.isfinite(held) and held>1.0)
check('leftButtonUpAfterNativeEnd',isinstance(s.get('pressedMouseButtons'),int) and s['pressedMouseButtons']&1==0)
check('operation',end.get('operation')==(16 if a.kind=='drop' else 0))
check('stateClearedAfterEnd',cleared(end.get('dragState',{})));check('stateRemainsCleared',cleared(s.get('dragState',{})))
check('savedOrder',s.get('savedOrder')==expected);check('displayOrder',s.get('displayOrder')==expected)
check('writes',s.get('orderWrites')==n);check('notifications',s.get('orderNotifications')==n)
r0,r1=rows(base),rows(s);need(len(r0)==len(r1)==5,'Missing five row snapshots')
check('rowIdentityRetained',set(r0)==set(r1) and all(r0[k].get('objectIdentity')==r1[k].get('objectIdentity') for k in r0))
check('alphaRestored',len(r1)==5 and all(abs(r.get('alpha',0)-1)<.001 for r in r1.values()))
check('activeRowFeedbackObserved',any(any(r.get('alpha',1)<.5 for r in x.get('rows',[])) for x in h))
check('visibilityUnchanged',s.get('visibility')==base.get('visibility') and s.get('visibilityNotifications')==0)
check('windowIdentityRetained',s.get('windowIdentity')==base.get('windowIdentity'))
check('settingsScrollRetained',s.get('settingsScrollViews')==base.get('settingsScrollViews'))
check('noMouseKeyboardCue',s.get('keyboardFocusVisible')==dict.fromkeys(default,False))
check('fixtureDoesNotGenerateInputOrCallbacks',s.get('fixtureGeneratesInput') is False and s.get('directDragCallbacks') is False)
check('guestVNCLabel',s.get('inputMethod')=='guest-VNC')
preflight=s.get('productionPreflightOverrides',{})
check('productionPreflightOverridesNil',preflight.get('available') is True and preflight.get('pressedMouseButtonsForTestIsNil') is True and preflight.get('nativeDragStartObserverForTestIsNil') is True)
verdict='unverified' if missing else ('passed' if all(checks.values()) else 'failed')
print(json.dumps({'schema':1,'case':a.case,'kind':a.kind,'verdict':verdict,'checks':checks,'missingEvidence':missing,'failedAssertions':[k for k,v in checks.items() if not v],'observedNativeSessionSeconds':held,'nativeSessionEvents':events,'scope':'WindowServer/AppKit native source callbacks from explicitly authorized guest VNC input, final persistence/state and mouse focus cue. This does not claim human mouse input or a frame-rate measurement.','inputSHA256':{k:hashlib.sha256(v).hexdigest() for k,v in raw.items()}},indent=2))
raise SystemExit({'passed':0,'failed':1,'unverified':78}[verdict])
