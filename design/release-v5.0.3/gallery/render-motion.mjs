import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

const directory=path.dirname(fileURLToPath(import.meta.url));
const project=path.resolve(directory,'../../..');
const [packageDirectory,scratch]=process.argv.slice(2);
const {chromium}=await import(pathToFileURL(path.join(packageDirectory,'index.mjs')).href);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const clock=await fs.readFile(path.join(project,'design/popover/power-icons-vector/clock.svg'),'utf8');
const source=await fs.readFile(path.join(directory,'full-charge-orbit.html'),'utf8');
const html=source.replace('{{CLOCK_SVG}}',clock);
const frames=path.join(scratch,'frames');await fs.mkdir(frames);
const errors=[];
const evidence={schema:1,version:'5.0.3',kind:'Animated approved-design preview; not a running-App screenshot',width:600,height:360,frames:640,fps:20,durationSeconds:32,loop:'infinite',sourceHTMLSHA256:hash(source),nativeGeometrySourceSHA256:hash(await fs.readFile(path.join(project,'Popover/FullChargeOrbit.swift'))),paletteSource:'PopoverStyle blue: light #0064CF, dark #0A84FF; all star/trail/sphere colors derive from that tint.',nativePeriodsSeconds:[8,10.6],designPeriodsSeconds:[8,32/3],innerPeriodAdjustmentPercent:((32/3)/10.6-1)*100,loopFit:'Four outer and three inner revolutions close at32s; inner cycle is approximately0.63% slower than native solely for this seamless design GIF. No fades, pauses or phase resets occur in the loop.',geometry:'Native fixed radii8.4/7.4, inclinations78/76deg, rolls+35/-32deg, camera70, opaque planet radius4, historical0.52s tapering ribbons split by depth, opposite directions and closed±6% speed modulation.',browserContextClosed:false,checks:[],assets:[]};
const context=await chromium.launchPersistentContext(path.join(scratch,'profile'),{
  executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,viewport:{width:600,height:360},deviceScaleFactor:1,
  args:['--disable-gpu','--disable-background-networking','--disable-component-update','--no-first-run'],
});
try{
  await context.route('**/*',route=>route.abort());
  const page=await context.newPage();page.on('pageerror',error=>errors.push(String(error)));
  await page.setContent(html,{waitUntil:'load'});await page.evaluate(()=>document.fonts.ready);
  evidence.browser=context.browser()?.version();
  const metrics=await page.evaluate(()=>({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,height:innerHeight,scrollHeight:document.documentElement.scrollHeight,headings:document.querySelector('h1').textContent}));
  if(metrics.scrollWidth!==600||metrics.scrollHeight!==360)throw new Error(`Unexpected canvas layout: ${JSON.stringify(metrics)}`);
  evidence.checks.push({name:'600x360 layout without overflow',passed:true});
  const geometry=await page.evaluate(()=>{
    const {sample,periods}=window.wattsonOrbitGeometry;
    return periods.map((period,orbit)=>{
      let front=false,back=false,maxRadius=0;
      for(let i=0;i<=2400;i++){const p=sample(orbit,period*i/2400),r=Math.hypot(p.x,p.y);maxRadius=Math.max(maxRadius,r);front ||= r<4&&p.z>4;back ||= r<4&&p.z< -4;}
      const a=sample(orbit,0),b=sample(orbit,32);
      return {orbit,frontSphereCrossing:front,backSphereCrossing:back,maxProjectedRadius:maxRadius,loopPositionError:Math.hypot(a.x-b.x,a.y-b.y,a.z-b.z)};
    });
  });
  if(geometry.some(g=>!g.frontSphereCrossing||!g.backSphereCrossing||g.loopPositionError>1e-9))throw new Error('Geometry/seam validation failed');
  evidence.geometryChecks=geometry;
  for(const theme of ['light','dark']){
    await page.evaluate(theme=>window.renderWattsonOrbit(0,theme),theme);
    await page.screenshot({path:path.join(directory,`full-charge-orbit-${theme}.png`)});
  }
  const first=await page.screenshot();
  await page.evaluate(()=>window.renderWattsonOrbit(32,'dark'));
  const closed=await page.screenshot();
  if(hash(first)!==hash(closed))throw new Error('The32s loop does not close pixel-identically');
  evidence.checks.push({name:'t0 and t32 pixel-identical loop closure',passed:true,sha256:hash(first)});
  await fs.copyFile(path.join(directory,'full-charge-orbit-dark.png'),path.join(directory,'full-charge-orbit-poster.png'));
  for(let frame=0;frame<640;frame++){
    await page.evaluate(time=>window.renderWattsonOrbit(time,'dark'),frame/20);
    await page.screenshot({path:path.join(frames,`frame-${String(frame).padStart(3,'0')}.png`)});
  }
  if(errors.length)throw new Error(errors.join('\n'));
}finally{
  await context.close();evidence.browserContextClosed=true;
}
const palette=path.join(scratch,'palette.png');
execFileSync('/opt/homebrew/bin/ffmpeg',['-v','error','-framerate','20','-i',path.join(frames,'frame-%03d.png'),'-vf','palettegen=max_colors=128:stats_mode=full','-frames:v','1',palette]);
const gif=path.join(directory,'full-charge-orbit.gif');
execFileSync('/opt/homebrew/bin/ffmpeg',['-v','error','-y','-framerate','20','-i',path.join(frames,'frame-%03d.png'),'-i',palette,'-lavfi','paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle','-gifflags','+offsetting+transdiff','-loop','0',gif]);
const ffprobe=JSON.parse(execFileSync('/opt/homebrew/bin/ffprobe',['-v','error','-select_streams','v:0','-show_entries','stream=width,height,nb_frames,duration','-of','json',gif],{encoding:'utf8'}));
evidence.encoded=ffprobe.streams[0];
if(+evidence.encoded.nb_frames!==640||+evidence.encoded.duration!==32)throw new Error('Unexpected encodedGIF timing');
const gifBytes=await fs.readFile(gif);
if(!gifBytes.includes(Buffer.from([0x4e,0x45,0x54,0x53,0x43,0x41,0x50,0x45,0x32,0x2e,0x30,0x03,0x01,0x00,0x00])))throw new Error('Infinite GIF loop extension is missing');
evidence.checks.push({name:'Encoded640-frame32sGIF with infinite loop extension',passed:true});
execFileSync('/opt/homebrew/bin/ffmpeg',['-v','error','-y','-i',gif,'-vf',"select='not(mod(n,80))',crop=164:148:408:145,scale=328:296:flags=lanczos,tile=4x2",'-frames:v','1',path.join(directory,'motion-review.png')]);
for(const name of ['full-charge-orbit.gif','full-charge-orbit-poster.png','full-charge-orbit-light.png','full-charge-orbit-dark.png']){
  const bytes=await fs.readFile(path.join(directory,name));evidence.assets.push({file:name,bytes:bytes.length,sha256:hash(bytes)});
}
evidence.pageErrors=errors;
await fs.writeFile(path.join(directory,'motion-provenance.json'),JSON.stringify(evidence,null,2)+'\n');
console.log(`Rendered 600x360 seamless 32s GIF; ${evidence.assets[0].bytes} bytes; browser closed; 640 frames.`);
