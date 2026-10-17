#!/usr/bin/env python3
"""Pure-data evaluator self-tests. Every generated callback is synthetic test data.

No generated state is production evidence; no app, VM, UI, or input runs here.
"""
import copy,hashlib,importlib.util,json,sys
from pathlib import Path
sys.dont_write_bytecode=True
base=Path(__file__).resolve().parent
repo=base.parents[2]
spec=importlib.util.spec_from_file_location('normal_drag_local_runtime',repo/'tests/local_runtime.py')
runtime=importlib.util.module_from_spec(spec);spec.loader.exec_module(runtime)
runtime.SCRATCH_ROOT=base/'data-mutation-scratch.noindex'
case='synthetic-evaluator-self-test'
default=['flow','ring','lanes','history','runtime']
clear={'available':True,'draggedModuleIsNil':True,'originalOrderIsEmpty':True,'dragSessionIsNil':True}
rows=[{'id':'settings.modules.row.'+n,'objectIdentity':'synthetic-row-'+n,'alpha':1} for n in default]
common={'case':case,'savedOrder':default,'displayOrder':default,'orderWrites':0,'orderNotifications':0,'observedOwnWindowEventCount':0,'lastCommand':{'result':'applied'},'rows':rows,'dragState':clear,'visibility':dict.fromkeys(default,True),'visibilityNotifications':0,'windowIdentity':'synthetic-window','settingsScrollViews':[{'objectIdentity':'synthetic-scroll','origin':[0,0]}],'keyboardFocusVisible':dict.fromkeys(default,False),'fixtureGeneratesInput':False,'directDragCallbacks':False,'inputMethod':'guest-VNC','pressedMouseButtons':0,'productionPreflightOverrides':{'available':True,'pressedMouseButtonsForTestIsNil':True,'nativeDragStartObserverForTestIsNil':True},'nativeDragObservation':{'installed':True,'originalIMPInvokedExactlyOncePerObservedCallback':True,'argumentsForwardedUnchanged':True,'callbacksGeneratedByFixture':False}}
def valid(kind):
 s=copy.deepcopy(common);s['observedOwnWindowEventCount']=4
 if kind=='drop':s.update(savedOrder=default[1:]+default[:1],displayOrder=default[1:]+default[:1],orderWrites=1,orderNotifications=1)
 phases=['willBegin.enter','willBegin.return','endedAt.enter','endedAt.return']
 s['nativeDragSessionEvents']=[{'phase':phase,'case':case,'sessionIdentity':'synthetic-session','sourceIdentity':'synthetic-source','syntheticCallback':False,'monotonicUptime':100+(1.5 if phase.startswith('endedAt') else 0),'pressedMouseButtons':0 if phase.startswith('endedAt') else 1,'operation':16 if kind=='drop' else 0,'dragState':clear} for phase in phases]
 return s
results=[]
def run_one(name,kind,mutate=None,expected=1,expected_check=None):
 s=valid(kind);active=copy.deepcopy(common);active['observedOwnWindowEventCount']=2;active['rows'][0]['alpha']=.25
 h=[copy.deepcopy(common),active]
 if mutate:mutate(s,h)
 h.append(s)
 with runtime.TemporaryDirectory(prefix='normal-drag-pure-data-') as directory:
  root=Path(directory);(root/'state.json').write_text(json.dumps(s)+'\n');(root/'history.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in h))
  r=runtime.run([sys.executable,str(base/'evaluate-normal-slow-drag.py'),str(root),'--case',case,'--kind',kind],capture_output=True,text=True,timeout=15)
  try:report=json.loads(r.stdout)
  except (ValueError,TypeError):report={'parseFailure':True,'stdout':r.stdout,'stderr':r.stderr}
  passed=r.returncode==expected and (expected_check is None or report.get('checks',{}).get(expected_check) is False)
  results.append({'name':name,'kind':kind,'expectedExit':expected,'actualExit':r.returncode,'expectedFailedCheck':expected_check,'evaluatorVerdict':report.get('verdict'),'failedChecks':report.get('failedAssertions'),'missingEvidence':report.get('missingEvidence'),'selfTestPassed':passed,'syntheticDataOnly':True})
run_one('synthetic-drop-positive-control','drop',expected=0)
run_one('synthetic-outside-positive-control','outside',expected=0)
run_one('missing-native-ended-pair','drop',lambda s,h:s.update(nativeDragSessionEvents=s['nativeDragSessionEvents'][:2]),78)
run_one('missing-native-begin-pair','drop',lambda s,h:s.update(nativeDragSessionEvents=s['nativeDragSessionEvents'][2:]),78)
run_one('missing-all-native-callbacks','drop',lambda s,h:s.update(nativeDragSessionEvents=[]),78)
def delta(s,h,n):
 for event in s['nativeDragSessionEvents']:
  if event['phase'].startswith('endedAt'):event['monotonicUptime']=100+n
run_one('short-native-session-0.99s','drop',lambda s,h:delta(s,h,.99),expected_check='nativeSessionHeldOverOneSecond')
run_one('boundary-exactly-1-second','drop',lambda s,h:delta(s,h,1),expected_check='nativeSessionHeldOverOneSecond')
run_one('boundary-over-1-second','drop',lambda s,h:delta(s,h,1.00001),expected=0)
run_one('nonfinite-native-duration','drop',lambda s,h:delta(s,h,float('nan')),expected_check='nativeSessionHeldOverOneSecond')
run_one('zero-native-start-button-mask','drop',lambda s,h:s['nativeDragSessionEvents'][0].update(pressedMouseButtons=0),expected_check='realLeftButtonDownAtNativeStart')
run_one('right-only-native-start-button-mask','drop',lambda s,h:s['nativeDragSessionEvents'][0].update(pressedMouseButtons=2),expected_check='realLeftButtonDownAtNativeStart')
run_one('pressed-buttons-seam-not-nil','drop',lambda s,h:s['productionPreflightOverrides'].update(pressedMouseButtonsForTestIsNil=False),expected_check='productionPreflightOverridesNil')
run_one('native-start-seam-not-nil','drop',lambda s,h:s['productionPreflightOverrides'].update(nativeDragStartObserverForTestIsNil=False),expected_check='productionPreflightOverridesNil')
run_one('seam-observation-unavailable','drop',lambda s,h:s['productionPreflightOverrides'].update(available=False),expected_check='productionPreflightOverridesNil')
run_one('wrong-native-session','drop',lambda s,h:s['nativeDragSessionEvents'][-1].update(sessionIdentity='synthetic-other'),expected_check='sameNativeSession')
run_one('wrong-native-source','drop',lambda s,h:s['nativeDragSessionEvents'][-1].update(sourceIdentity='synthetic-other'),expected_check='sameNativeSource')
run_one('extra-native-callback','drop',lambda s,h:s['nativeDragSessionEvents'].append(copy.deepcopy(s['nativeDragSessionEvents'][-1])),expected_check='exactNativeCallbackSequence')
run_one('extra-order-write','drop',lambda s,h:s.update(orderWrites=2),expected_check='writes')
run_one('extra-order-notification','drop',lambda s,h:s.update(orderNotifications=2),expected_check='notifications')
run_one('unexpected-write-on-outside','outside',lambda s,h:s.update(orderWrites=1),expected_check='writes')
run_one('wrong-final-order','drop',lambda s,h:s.update(savedOrder=default),expected_check='savedOrder')
run_one('stuck-half-transparent-row','drop',lambda s,h:s['rows'][0].update(alpha=.55),expected_check='alphaRestored')
run_one('stuck-native-state','drop',lambda s,h:s['dragState'].update(dragSessionIsNil=False),expected_check='stateRemainsCleared')
run_one('button-remains-down','drop',lambda s,h:s.update(pressedMouseButtons=1),expected_check='leftButtonUpAfterNativeEnd')
run_one('observer-does-not-forward-original','drop',lambda s,h:s['nativeDragObservation'].update(originalIMPInvokedExactlyOncePerObservedCallback=False),expected_check='originalIMPForwarded')
run_one('wrong-input-label','drop',lambda s,h:s.update(inputMethod='human-mouse'),expected_check='guestVNCLabel')
run_one('no-active-feedback','drop',lambda s,h:h[1]['rows'][0].update(alpha=1),expected_check='activeRowFeedbackObserved')
run_one('no-reset-baseline','drop',lambda s,h:h[0].update(lastCommand={'result':'rejected-active-gesture'}),78)
report={'schema':1,'kind':'PURE_DATA_EVALUATOR_SELF_TESTS','productionPassClaim':False,'VMStarted':False,'AppCompiledOrLaunched':False,'inputInjected':False,'syntheticPositiveControlsAreNotProductEvidence':True,'tests':results,'passed':sum(r['selfTestPassed'] for r in results),'count':len(results),'evaluatorSHA256':hashlib.sha256((base/'evaluate-normal-slow-drag.py').read_bytes()).hexdigest()}
(base/'evaluator-mutation-results.json').write_text(json.dumps(report,indent=2)+'\n')
if runtime.SCRATCH_ROOT.is_dir():runtime.SCRATCH_ROOT.rmdir()
print(json.dumps({'kind':report['kind'],'passed':report['passed'],'count':report['count'],'productionPassClaim':False,'ownedScratchRemoved':not runtime.SCRATCH_ROOT.exists()}))
if not all(r['selfTestPassed'] for r in results):raise SystemExit(1)
