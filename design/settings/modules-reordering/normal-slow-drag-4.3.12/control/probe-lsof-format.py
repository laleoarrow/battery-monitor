import socket,os,subprocess,importlib.util,json,pathlib,datetime
root=pathlib.Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('guard_readonly',root/'vm-owner/vnc-guard.py');g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
with socket.socket() as s:
 s.bind(('127.0.0.1',0));s.listen(1)
 r=subprocess.run(['/usr/sbin/lsof','-nP','-a','-p',str(os.getpid()),'-iTCP','-sTCP:LISTEN','-Ts','-F0pcfnT'],capture_output=True,timeout=3)
 report={'atUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'knownOwnedBind':list(s.getsockname()),'actualLsofFields':r.stdout.decode().split('\0'),'actualLsofExit':r.returncode,'noAuthentication':True,'noInput':True}
 try:report['parsed']=g.listeners('/usr/sbin/lsof',os.getpid());report['parserAccepted']=True
 except Exception as e:report['parserAccepted']=False;report['errorType']=type(e).__name__;report['error']=str(e)
report['ownedSocketClosed']=s.fileno()==-1
(root/'control/actual-lsof-format-probe.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'parserAccepted':report['parserAccepted'],'socketClosed':report['ownedSocketClosed']}))
