from pathlib import Path
import subprocess,json,hashlib
base=Path(__file__).resolve().parent
refs=('5d5c896b7a1531ce4f9783fa467ff8c8eb62b82e','8529889597961de756fa57397b1d1149d6d1b536')
def read(ref,path):return subprocess.check_output(['git','show',ref+':'+path])
def region(data,start,end=None):
 a=data.index(start)
 return data[a:data.index(end,a)] if end else data[a:]
settings=[read(r,'MenuBar/SettingsWindowController.swift') for r in refs]
art=[read(r,'MenuBar/ModuleIconArtwork.swift') for r in refs]
regions={'Settings suffix including all Modules classes and window controller':[region(x,b'private final class MenuBarIconCardButton:') for x in settings], 'Existing module and sidebar artwork':[region(x,b'    static func image(for module:',b'    static func generalImage(') if b'    static func generalImage(' in x else region(x,b'    static func image(for module:',b'    private static func') for x in art]}
checks={}
for n,parts in regions.items():checks[n]={'equal':parts[0]==parts[1],'sha256':[hashlib.sha256(x).hexdigest() for x in parts]}
files=subprocess.check_output(['git','ls-tree','-r','--name-only',refs[0],'Core','MenuBar','Popover'],text=True).splitlines();files=[p for p in files if p.endswith('.swift')]
other=[p for p in files if p not in ('MenuBar/ModuleIconArtwork.swift','MenuBar/SettingsWindowController.swift')]
report={'testedSource':refs[0],'testedVersion':'4.3.12','newCandidateSource':refs[1],'newCandidateVersion':'4.3.13','actualExecutionClaimForNewCandidate':False,'scope':'Source equivalence for Modules interaction only, not complete 4.3.13 native acceptance or installation','identicalOtherSwiftFiles':[p for p in other if read(refs[0],p)==read(refs[1],p)],'changedOtherSwiftFiles':[p for p in other if read(refs[0],p)!=read(refs[1],p)],'regionChecks':checks}
(base/'source-applicability-4.3.13.json').write_text(json.dumps(report,indent=2)+'\n')
print({n:v['equal'] for n,v in checks.items()});print('unchangedOther',len(report['identicalOtherSwiftFiles']),'changedOther',len(report['changedOtherSwiftFiles']))
