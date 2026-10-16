from pathlib import Path
from PIL import Image,ImageDraw
import json,sys
p=Path(sys.argv[1]).resolve();r=json.loads((p/'axis-motion.json').read_text()); source=sys.argv[2]
assert len(source)==40
choices=[]
for name in ['scale-expansion','scale-contraction','repeated-scroll','departing-outlier-contraction','gradient-alpha-contraction']:
 rows=[f for f in r['frames'] if f['phase']==name and 0<=f['phaseElapsedSeconds']<1]
 for target in [0,.2,.7]: choices.append(min(rows,key=lambda f:abs(f['phaseElapsedSeconds']-target)))
w,h=Image.open(p/'recording-frames'/choices[0]['file']).size
sheet=Image.new('RGB',(w*3,(h+32)*5),(24,26,28));draw=ImageDraw.Draw(sheet)
for i,f in enumerate(choices):
 x=(i%3)*w;y=(i//3)*(h+32)
 draw.text((x+6,y+5),f"{f['phase']} {f['phaseElapsedSeconds']:.3f}s",fill='white')
 sheet.paste(Image.open(p/'recording-frames'/f['file']).convert('RGB'),(x,y+32))
sheet.save(p/'selected-native-frames.png')
(p/'selected-native-frames.json').write_text(json.dumps(choices,indent=2)+'\n')
fill=[];width=[]
for f in r['frames']:
 if not 0<=f['phaseElapsedSeconds']<1: continue
 im=Image.open(p/'recording-frames'/f['file']).convert('RGB')
 if f['phase'] in ['repeated-scroll','departing-outlier-contraction','gradient-alpha-contraction'] and f['phaseElapsedSeconds']<.5:
  y=im.height-40;left=im.getpixel((4,y));reference=im.getpixel((20,y))
  fill.append({'phase':f['phase'],'file':f['file'],'phaseElapsed':f['phaseElapsedSeconds'],'row':y,'leftX4':left,'referenceX20':reference,'leftVsX20MaxChannelDifference':max(abs(a-b) for a,b in zip(left,reference))})
 if f['phase'] in ['departing-outlier-contraction','gradient-alpha-contraction']:
  col=im.width//2
  stroke_rows=[y for y in range(im.height) if (v:=im.getpixel((col,y)))[2]>140 and v[2]-v[0]>100 and v[1]>70]
  width.append({'phase':f['phase'],'file':f['file'],'phaseElapsed':f['phaseElapsedSeconds'],'x':col,'strokeRows':stroke_rows,'thresholdedVerticalPixels':len(stroke_rows),'passed':2<=len(stroke_rows)<=4})
for item in fill:
 item['nearbyRowHasVisibleFill']=item['referenceX20']!=(28,31,36)
 item['expectedFillComparison']=item['phase']!='repeated-scroll' and item['nearbyRowHasVisibleFill']
 item['passedWhenComparable']=(item['leftVsX20MaxChannelDifference']==0) if item['expectedFillComparison'] else None
report={'allComparableOutlierFillChecksPassed':all(item['passedWhenComparable'] is not False for item in fill),'schema':1,'sourceCommit':source,'leftFillPixels':fill,'flatStrokeThickness':width,'allThicknessChecksPassed':all(f['passed'] for f in width),
 'scope':'Actual 2x WindowServer native pixels. Flat central stroke threshold B>140, B-R>100,G>70 distinguishes stroke from fill. Antialiased 1.6-point stroke allows 2–4 thresholded pixels. Left fill compares same-row pixels x4/x20 when under visible curve; startup left history can legitimately be blank. Not a frame-rate benchmark.'}
(p/'native-pixel-review.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'pixelWidthChecks':len(width),'allWidthPassed':report['allThicknessChecksPassed'],'observedStrokePixels':sorted(set(f['thresholdedVerticalPixels'] for f in width)),'outlierFillDifferences':sorted(set(f['leftVsX20MaxChannelDifference'] for f in fill if f['phase']!='repeated-scroll'))},indent=2))
assert report['allThicknessChecksPassed']
