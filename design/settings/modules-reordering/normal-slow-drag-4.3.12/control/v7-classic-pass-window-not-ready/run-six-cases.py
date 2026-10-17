from pathlib import Path
import json,subprocess,time,os,hashlib,sys,signal
base=Path(__file__).resolve().parent.parent
live=base/'normal-slow-drag-v7/drag/manual-classic-0'
vm='Wattson-NormalSlowDrag-20261017'
share='/Volumes/My Shared Files/normaldrag'
probe='/Users/admin/Project/Wattson-NormalSlowDrag-QA/.build/control-lease.noindex/guest-lease'
command_index=0
def owned(command, timeout):
 global command_index
 command_index+=1
 runner=base.parents[1]/'scripts/lib/run_owned.py'
 mask=signal.pthread_sigmask(signal.SIG_BLOCK,{signal.SIGHUP,signal.SIGINT,signal.SIGTERM})
 try:
  child=subprocess.Popen([sys.executable,str(runner),'--grace','8','--timeout',str(timeout),'--',*command],stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True,preexec_fn=lambda:signal.pthread_sigmask(signal.SIG_SETMASK,mask))
 except BaseException:
  signal.pthread_sigmask(signal.SIG_SETMASK,mask)
  raise
 try:
  signal.pthread_sigmask(signal.SIG_SETMASK,mask)
  out,err=child.communicate()
 except BaseException:
  child.send_signal(signal.SIGTERM)
  try:out,err=child.communicate(timeout=12)
  except subprocess.TimeoutExpired:
   os.killpg(child.pid,signal.SIGKILL);out,err=child.communicate()
  (base/'control'/f'interrupted-command-{command_index}.stdout').write_bytes(out)
  (base/'control'/f'interrupted-command-{command_index}.stderr').write_bytes(err)
  raise
 return subprocess.CompletedProcess(command,child.returncode,out,err)
def interrupted(number,frame):raise SystemExit(128+number)
for number in (signal.SIGHUP,signal.SIGINT,signal.SIGTERM):signal.signal(number,interrupted)
def atomic(path,data):
 if path.parent!=live or path.name not in ('reset.json','capture.json'):raise ValueError('Unexpected fixture command path')
 payload=json.dumps(data)+'\n'
 guest_path=share+'/'+str(path.relative_to(base))
 script="""import hashlib,json,os,signal,sys,tempfile
def interrupted(number,frame):raise SystemExit(128+number)
for number in (signal.SIGHUP,signal.SIGINT,signal.SIGTERM):signal.signal(number,interrupted)
path,payload=sys.argv[1:]
previous_mask=signal.pthread_sigmask(signal.SIG_BLOCK,{signal.SIGHUP,signal.SIGINT,signal.SIGTERM})
fd,temporary=tempfile.mkstemp(prefix='.command-',dir=os.path.dirname(path))
try:
 with os.fdopen(fd,'w') as output:
  signal.pthread_sigmask(signal.SIG_SETMASK,previous_mask)
  output.write(payload)
 os.replace(temporary,path)
 actual=open(path,'rb').read()
 print(json.dumps({'path':path,'sha256':hashlib.sha256(actual).hexdigest(),'byteCount':len(actual),'inode':os.stat(path).st_ino}))
finally:
 try:os.unlink(temporary)
 except FileNotFoundError:pass
"""
 result=owned(['/opt/homebrew/bin/tart','exec',vm,'/usr/bin/python3','-c',script,guest_path,payload],20)
 if result.returncode:raise RuntimeError('Guest command publication failed '+str(result.returncode))
 publication=json.loads(result.stdout)
 if publication['path']!=guest_path or publication['sha256']!=hashlib.sha256(payload.encode()).hexdigest():raise RuntimeError('Guest command readback mismatch')
 with (base/'control/guest-command-publications.jsonl').open('a') as output:output.write(json.dumps(publication)+'\n')
def wait(predicate,seconds=15):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  try:
   state=json.loads((live/'state.json').read_bytes())
   if predicate(state):return state
  except (FileNotFoundError,json.JSONDecodeError):pass
  time.sleep(.15)
 raise TimeoutError('Fixture state predicate timed out')
results=[]
assert (live/'compiled-ready.json').is_file() and not (live/'start-manual').exists()
try:
 (live/'start-manual').touch()
 wait(lambda s:s.get('visible') and s.get('keyWindow'),30)
 for style in ('classic','standard','clear'):
  for kind in ('drop','outside'):
   name=style+'-slow-'+kind
   folder=base/'normal-slow-drag-v7/cases'/name;folder.mkdir(parents=True,exist_ok=False)
   atomic(live/'reset.json',{'case':name,'style':style,'reduceMotion':False})
   state=wait(lambda s:s.get('case')==name and s.get('style')==style and s.get('reduceMotion') is False and len(s.get('rows',[]))==5 and s.get('lastCommand',{}).get('result')=='applied' and s.get('pressedMouseButtons')==0 and s.get('observedOwnWindowEventCount')==0 and s.get('keyWindow') and all(r.get('alpha')==1 for r in s.get('rows',[])))
   if kind=='drop':
    target_check=state.get('inputGeometry',{}).get('dropTargetHitTest',{})
    if not all(target_check.get(key) is True for key in ('passedBool','containsExactStack','candidateGeometryValid')):raise RuntimeError('Drop point does not hit valid interior of exact production list')
   # Freeze exact bytes before independently resolving guest process/window/display lease.
   (folder/'before-state.json').write_bytes((live/'state.json').read_bytes())
   guest_state=share+'/normal-slow-drag-v7/cases/'+name+'/before-state.json'
   p=owned(['/opt/homebrew/bin/tart','exec',vm,probe,guest_state],20)
   (folder/'lease-stderr.txt').write_bytes(p.stderr)
   (folder/'lease.json').write_bytes(p.stdout)
   if p.returncode:raise RuntimeError('Guest lease probe failed '+str(p.returncode))
   command=[sys.executable,str(base/'vnc/direct_vz_loopback.py'),'--owner',str(base/'control/direct-owner.json'),'--lease',str(folder/'lease.json'),'--password',str(base/'private/direct-vz-password'),'--state',str(folder/'before-state.json'),'--kind',kind,'--report',str(folder/'input.json')]
   p=owned(command,20)
   (folder/'input-stdout.txt').write_bytes(p.stdout);(folder/'input-stderr.txt').write_bytes(p.stderr)
   if p.returncode:raise RuntimeError('Guest VNC driver failed '+str(p.returncode))
   driver=json.loads((folder/'input.json').read_bytes())
   down=[e for e in driver['events'] if e['mask']==1]
   release=driver['events'][-1]
   held=release['attemptedAtSystemMonotonic']-down[0]['attemptedAtSystemMonotonic'] if down else 0
   timing={'postedHeldSeconds':held,'heldMessages':len(down),'plannedDragMoves':60,'calibrationObservedMovement':driver.get('calibration',{}).get('observedMovement') is True,'calibrationPassed':driver.get('calibration',{}).get('passed') is True,'socketClosed':driver['socketClosed'],'releaseMask':release['mask']}
   (folder/'input-timing-check.json').write_text(json.dumps(timing,indent=2)+'\n')
   if not (held>=2.29 and len(down)==61 and release['mask']==0 and timing['calibrationObservedMovement'] and timing['calibrationPassed'] and timing['socketClosed']):raise RuntimeError('Actual posted timing/calibration gate failed')
   wait(lambda s:s.get('case')==name and any(e.get('phase')=='endedAt.return' for e in s.get('nativeDragSessionEvents',[])) and s.get('pressedMouseButtons')==0 and all(r.get('alpha')==1 for r in s.get('rows',[])),20)
   time.sleep(.35)
   for file in ('state.json','history.jsonl'):(folder/file).write_bytes((live/file).read_bytes())
   p=owned([sys.executable,str(base/'fixture/evaluate-normal-slow-drag.py'),str(folder),'--case',name,'--kind',kind],10)
   (folder/'evaluation.json').write_bytes(p.stdout);(folder/'evaluation-stderr.txt').write_bytes(p.stderr)
   verdict=json.loads(p.stdout);results.append({'case':name,'exitCode':p.returncode,'verdict':verdict['verdict'],'observedNativeSessionSeconds':verdict['observedNativeSessionSeconds'],'failedAssertions':verdict['failedAssertions'],'missingEvidence':verdict['missingEvidence']})
   print(json.dumps(results[-1]),flush=True)
   # Optional exact owned-window image; its outcome is independent of native verdict.
   atomic(live/'capture.json',{'name':name+'-final'})
   try:
    captured=wait(lambda s:s.get('lastCapture',{}).get('name')==name+'-final',8)
    (folder/'capture-status.json').write_text(json.dumps(captured['lastCapture'],indent=2)+'\n')
    image=live/(name+'-final.png')
    if image.exists():(folder/'window.png').write_bytes(image.read_bytes())
   except TimeoutError:(folder/'capture-status.json').write_text('{"result":"unverified-timeout"}\n')
   if p.returncode:raise RuntimeError('Native observer did not pass '+name)
except BaseException as error:
 for file in ('state.json','history.jsonl'):
  if (live/file).is_file():(base/'control'/('failure-'+file)).write_bytes((live/file).read_bytes())
 (base/'control/cases-error.json').write_text(json.dumps({'errorType':type(error).__name__,'error':str(error),'completedCases':results},indent=2)+'\n')
 raise
finally:
 for number in (signal.SIGHUP,signal.SIGINT,signal.SIGTERM):signal.signal(number,signal.SIG_IGN)
 try:
  (base/'control/cases-summary.json').write_text(json.dumps({'sourceCommit':'5d5c896b7a1531ce4f9783fa467ff8c8eb62b82e','version':'4.3.12','inputMethod':'owned-copy-loopback-directVZ-VNC','humanMouseInput':False,'hostInput':False,'controllerPublicationMethod':'guest atomic replace with exact readback','results':results,'allSixPassed':len(results)==6 and all(x['verdict']=='passed' for x in results)},indent=2)+'\n')
 finally:
  (live/'done').touch()
