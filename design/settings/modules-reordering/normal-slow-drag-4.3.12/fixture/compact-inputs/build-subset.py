#!/usr/bin/env python3
"""Derive immutable source bytes only; never launch an app, VM or input tool."""
from pathlib import Path, PurePosixPath
import gzip,hashlib,io,json,os,subprocess,tarfile
base=Path(__file__).resolve().parent
repo=base.parents[3]
output=Path(os.environ['WATTSON_SUBSET_OUTPUT'])
assert output.is_dir() and output.resolve().parent==base.resolve(), 'Use the owned build-subset.sh wrapper'
full=repo/'.build/modules-default-sidebar-review.noindex/source-5d5c896b7a15.tar.gz'
commit='5d5c896b7a1531ce4f9783fa467ff8c8eb62b82e'
full_sha='8aa52b90ec8f2e7f93e2ccc7ebc2fd9ab7e89217a95bfd93edccbb3e90156ca3'
assert hashlib.sha256(full.read_bytes()).hexdigest()==full_sha
extra={'VERSION','scripts/lib/local_cleanup.sh','scripts/lib/run_owned.py',*[f'design/icon/in-app-logo/{name}.png' for name in ('AppLogoColor','AppLogoClearLight','AppLogoClearDark')]}
selected={}
with tarfile.open(full,'r:gz') as source:
 for member in source.getmembers():
  path=PurePosixPath(member.name)
  production=member.isfile() and member.name.startswith(('Core/','MenuBar/','Popover/')) and member.name.endswith('.swift')
  if not production and member.name not in extra:continue
  assert member.isfile() and not path.is_absolute() and '..' not in path.parts
  data=source.extractfile(member).read()
  git=subprocess.check_output(['git','show',commit+':'+member.name],cwd=repo)
  assert data==git,member.name
  blob=subprocess.check_output(['git','rev-parse',commit+':'+member.name],cwd=repo,text=True).strip()
  selected[member.name]=(data,member.mode,blob)
assert extra.issubset(selected)
assert len([n for n in selected if n.endswith('.swift')])==52
assert len([n for n in selected if n.endswith('.swift') and PurePosixPath(n).parent.as_posix() in ('Core','MenuBar','Popover')])==47
assert selected['VERSION'][0].decode().strip()=='4.3.12'
archive=output/'source-5d5c896b7a15-native-build-inputs-subset.tar.gz'
assert not archive.exists(),'The subset archive is immutable once written'
with archive.open('xb') as raw:
 with gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=0) as packed:
  with tarfile.open(fileobj=packed,mode='w',format=tarfile.PAX_FORMAT) as out:
   for name,(data,mode,blob) in sorted(selected.items()):
    item=tarfile.TarInfo(name);item.size=len(data);item.mode=mode;item.mtime=0;item.uid=0;item.gid=0
    out.addfile(item,io.BytesIO(data))
records=[]
for name,(data,mode,blob) in sorted(selected.items()):
 top_swift=name.endswith('.swift') and PurePosixPath(name).parent.as_posix() in ('Core','MenuBar','Popover')
 records.append({'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'originalFullArchiveMember':name,'matchesFullArchiveBytes':True,'gitCommit':commit,'gitBlobObjectID':blob,'matchesGitBlobBytes':True,'compiledByProductionTopLevelSwiftGlobs':top_swift,'includedByCurrentRuntimeBeforeAfterHashAudit':top_swift})
manifest={'schema':1,'kind':'EXACT_NATIVE_BUILD_INPUT_SUBSET_NOT_ORIGINAL_FULL_SOURCE_ARCHIVE','sourceCommit':commit,'appVersion':'4.3.12','originalFullSourceArchive':{'path':str(full),'sha256':full_sha,'bytes':full.stat().st_size,'wholeArchivePreservedInThisSubsetDirectory':False},'subsetArchive':{'name':archive.name,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'bytes':archive.stat().st_size,'memberCount':len(records)},'productionSwiftCounts':{'allRecursiveImmutableIdentityFiles':52,'topLevelCompileGlobFiles':47,'runtimeBeforeAfterTopLevelAuditFiles':47,'CoreDiagnosticsNotIncludedInTopLevelAuditOrCompileGlobs':5},'members':records,'productionSourceModified':False,'nativeFixtureToolsCopiedHere':False,'clientOrControlToolsCopiedHere':False,'secretsOrRunnableArtifactsIncluded':False,'VMStarted':False,'AppCompiledOrLaunched':False,'inputInjected':False}
(output/'subset-member-mapping.json').write_text(json.dumps(manifest,sort_keys=True,indent=2)+'\n')
(output/'MEMBER_SHA256SUMS.txt').write_text(''.join(r['sha256']+'  '+r['path']+'\n' for r in records))
with tarfile.open(archive) as verify:
 assert len(verify.getmembers())==len(records)
 for member in verify.getmembers():
  assert member.isfile() and verify.extractfile(member).read()==selected[member.name][0]
print(json.dumps({'subsetArchiveSHA256':manifest['subsetArchive']['sha256'],'subsetBytes':archive.stat().st_size,'members':len(records),'allRecursiveSwift':52,'runtimeAndCompiledTopLevelSwift':47,'originalArchiveBytes':full.stat().st_size,'everyMemberMatchesOriginalAndGit':True}))
