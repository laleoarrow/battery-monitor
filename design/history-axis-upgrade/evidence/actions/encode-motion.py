from pathlib import Path
import json, subprocess, sys
p=Path(sys.argv[1]).resolve()
r=json.loads((p/'axis-motion.json').read_text())
assert r['mode']=='frames' and r['frameCaptureRunsOffMainThread'] is True
assert len(r['frames'])>30
phases=list(dict.fromkeys(f['phase'] for f in r['frames']))
output=[]
for phase in phases:
 frames=[f for f in r['frames'] if f['phase']==phase and 0<=f['phaseElapsedSeconds']<1]
 assert len(frames)>=3, (phase,len(frames))
 entries=['ffconcat version 1.0']
 for i,frame in enumerate(frames):
  path=p/'recording-frames'/frame['file']
  assert path.is_file() and not path.is_symlink() and "'" not in str(path)
  entries.append("file '"+str(path)+"'")
  duration=frames[i+1]['elapsedSeconds']-frame['elapsedSeconds'] if i+1<len(frames) else 1/30
  assert 0<duration<1
  entries.append('duration '+str(duration))
 concat=p/(phase+'.ffconcat'); concat.write_text('\n'.join(entries)+'\n')
 movie=p/(phase+'.mp4'); assert not movie.exists()
 with (p/(phase+'-encode.log')).open('x') as log:
  subprocess.run(['/opt/homebrew/bin/ffmpeg','-hide_banner','-loglevel','warning','-f','concat','-safe','0','-i',str(concat),'-vf','pad=ceil(iw/2)*2:ceil(ih/2)*2','-c:v','libx264','-pix_fmt','yuv420p','-movflags','+faststart','-fps_mode','vfr',str(movie)],stdout=log,stderr=log,check=True)
 intervals=[b['elapsedSeconds']-a['elapsedSeconds'] for a,b in zip(frames,frames[1:])]
 output.append({'phase':phase,'frameCount':len(frames),'measuredDuration':frames[-1]['elapsedSeconds']-frames[0]['elapsedSeconds'],
                'largestFrameInterval':max(intervals),'movie':movie.name,
                'scope':'Actual native own-window recording; VFR encoding uses measured capture timestamps, without synthetic interpolation.'})
(p/'movies.json').write_text(json.dumps(output,indent=2)+'\n')
print(json.dumps(output,indent=2))
