from pathlib import Path
import json,subprocess,time,os,hashlib,sys
base=Path(__file__).resolve().parent.parent
live=base/'normal-slow-drag-v3/drag/manual-classic-0'
vm='Wattson-NormalSlowDrag-20261017'
share='/Volumes/My Shared Files/normaldrag'
probe='/Users/admin/Project/Wattson-NormalSlowDrag-QA/.build/control-lease.noindex/guest-lease'
def atomic(path,data):
 tmp=path.with_suffix(path.suffix+'.pending')
 tmp.write_text(json.dumps(data)+'\n');os.replace(tmp,path)
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
(live/'start-manual').touch()
try:
 wait(lambda s:s.get('visible') and s.get('keyWindow'),30)
 for style in ('classic','standard','clear'):
  for kind in ('drop','outside'):
   name=style+'-slow-'+kind
   folder=base/'normal-slow-drag-v3/cases'/name;folder.mkdir(parents=True,exist_ok=False)
   atomic(live/'reset.json',{'case':name,'style':style,'reduceMotion':False})
   wait(lambda s:s.get('case')==name and s.get('style')==style and s.get('reduceMotion') is False and len(s.get('rows',[]))==5 and s.get('lastCommand',{}).get('result')=='applied' and s.get('pressedMouseButtons')==0 and s.get('observedOwnWindowEventCount')==0 and s.get('keyWindow') and all(r.get('alpha')==1 for r in s.get('rows',[])))
   # Freeze exact bytes before independently resolving guest process/window/display lease.
   (folder/'before-state.json').write_bytes((live/'state.json').read_bytes())
   guest_state=share+'/normal-slow-drag-v3/cases/'+name+'/before-state.json'
   p=subprocess.run(['/opt/homebrew/bin/tart','exec',vm,probe,guest_state],capture_output=True,timeout=20)
   (folder/'lease-stderr.txt').write_bytes(p.stderr)
   (folder/'lease.json').write_bytes(p.stdout)
   if p.returncode:raise RuntimeError('Guest lease probe failed '+str(p.returncode))
   command=[sys.executable,str(base/'vnc/slow_vnc.py'),'--owner',str(base/'vm-owner/ready-r2.json'),'--lease',str(folder/'lease.json'),'--password',str(base/'private/vnc-password'),'--state',str(folder/'before-state.json'),'--kind',kind,'--report',str(folder/'input.json')]
   p=subprocess.run(command,capture_output=True,timeout=20)
   (folder/'input-stdout.txt').write_bytes(p.stdout);(folder/'input-stderr.txt').write_bytes(p.stderr)
   if p.returncode:raise RuntimeError('Guest VNC driver failed '+str(p.returncode))
   wait(lambda s:s.get('case')==name and any(e.get('phase')=='endedAt.return' for e in s.get('nativeDragSessionEvents',[])) and s.get('pressedMouseButtons')==0 and all(r.get('alpha')==1 for r in s.get('rows',[])),20)
   time.sleep(.35)
   for file in ('state.json','history.jsonl'):(folder/file).write_bytes((live/file).read_bytes())
   p=subprocess.run([sys.executable,str(base/'fixture/evaluate-normal-slow-drag.py'),str(folder),'--case',name,'--kind',kind],capture_output=True,timeout=10)
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
 (base/'control/cases-summary.json').write_text(json.dumps({'sourceCommit':'5d5c896b7a1531ce4f9783fa467ff8c8eb62b82e','version':'4.3.12','inputMethod':'guest-VNC','humanMouseInput':False,'hostInput':False,'results':results,'allSixPassed':len(results)==6 and all(x['verdict']=='passed' for x in results)},indent=2)+'\n')
 (live/'done').touch()
