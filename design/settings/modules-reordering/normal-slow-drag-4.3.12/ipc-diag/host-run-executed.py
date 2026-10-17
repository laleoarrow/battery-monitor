import pathlib, subprocess, time, json, os, uuid, hashlib, shutil, signal
base=pathlib.Path(__file__).resolve().parent
root=base.parents[2]
run=base/('data-'+uuid.uuid4().hex)
run.mkdir()
proc=None
report={'sourceSHA256':hashlib.sha256((base/'reader.swift').read_bytes()).hexdigest(),'hostWrites':[],'inputGenerated':False,'applicationStarted':False}
try:
    for name,value in [('host-replaced.json','host-0'),('guest-replaced.json','guest-0')]:
        (run/name).write_text(value)
    with (base/'guest-raw.jsonl').open('w') as output,(base/'guest-stderr.log').open('w') as error:
        proc=subprocess.Popen(['/usr/bin/python3',str(root/'scripts/lib/run_owned.py'),'--grace','3','--timeout','25','--','/opt/homebrew/bin/tart','exec','Wattson-NormalSlowDrag-20261017','/bin/bash','/Volumes/My Shared Files/normaldrag/ipc-diag/guest-run.sh',run.name],stdout=output,stderr=error)
        deadline=time.monotonic()+15
        while not (run/'reader-ready').is_file():
            if proc.poll() is not None: raise RuntimeError('guest exited before reader ready')
            if time.monotonic()>deadline: raise TimeoutError('reader-ready deadline')
            time.sleep(.05)
        start=time.monotonic()
        for step,target in [(1,1),(2,3)]:
            while time.monotonic()-start<target: time.sleep(.02)
            path=run/'host-replaced.json'; before=path.stat()
            tmp=run/('replace-'+str(step));tmp.write_text('host-'+str(step));os.replace(tmp,path)
            after=path.stat()
            report['hostWrites'].append({'step':step,'epoch':time.time(),'elapsed':time.monotonic()-start,'value':path.read_text(),'inodeBefore':before.st_ino,'inodeAfter':after.st_ino,'mtimeEpoch':after.st_mtime})
        report['guestActualExitCode']=proc.wait(timeout=13)
    events=[json.loads(line) for line in (base/'guest-raw.jsonl').read_text().splitlines()]
    report['guestObservedValues']={name:list(dict.fromkeys(e['value'] for e in events if e.get('event')=='read' and e['name']==name)) for name in ['host-replaced.json','guest-replaced.json','local.json']}
    report['guestAtomicWriteErrors']=[e for e in events if e.get('event')=='guest-write-error']
    report['hostLastValue']=(run/'host-replaced.json').read_text()
except BaseException as exc:
    report['error']=repr(exc)
    raise
finally:
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try: proc.wait(timeout=5)
        except subprocess.TimeoutExpired: proc.kill();proc.wait()
    shutil.rmtree(run)
    report['hostTemporaryMarkersRemoved']=not run.exists()
    (base/'report.json').write_text(json.dumps(report,indent=2)+'\n')
