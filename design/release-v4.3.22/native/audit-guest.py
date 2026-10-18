#!/usr/bin/env python3
import json, pathlib, subprocess, sys, time
home = pathlib.Path.home()
scratch = home / 'Project/.release-v4.3.22-native.noindex'
result = pathlib.Path(sys.argv[1])
result.mkdir(parents=True, exist_ok=True)
prefixes = ('com.leoarrow.wattson.interactiontests.', 'Wattson.SettingsCommandInteraction.')
def entries(directory):
    return sorted(str(p.relative_to(home)) for p in directory.iterdir() if p.name.startswith(prefixes)) if directory.exists() else []
def output(args):
    p = subprocess.run(args, capture_output=True, text=True, timeout=20)
    assert p.returncode == 0, (args, p.stderr)
    return p.stdout
start = time.monotonic(); unexpected = []; count = 0
while time.monotonic() - start < 35:
    count += 1
    prefs = entries(home / 'Library/Preferences')
    if prefs:
        unexpected.append({'elapsed': round(time.monotonic() - start, 3), 'preferences': prefs})
    time.sleep(.1)
(result / 'preferences-observation.json').write_text(json.dumps({'durationSeconds':round(time.monotonic()-start,3),'filesystemChecks':count,'unexpectedPreferences':unexpected,'allPassed':not unexpected,'method':'Filesystem-only observation after gate script cleanup; no defaults reads.'},indent=2)+'\n')
processes = [line.strip() for line in output(['/bin/ps','-axww','-o','pid=,command=']).splitlines() if '/Project/.release-v4.3.22-native.noindex/' in line]
registrar = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
registrations = [line.strip() for line in output([registrar,'-dump']).splitlines() if '/Project/.release-v4.3.22-native.noindex/' in line]
mounts = [line for line in output(['/sbin/mount']).splitlines() if '/Project/.release-v4.3.22-native.noindex/' in line]
checks = {'sourceAndBuildScratchRemoved':not scratch.exists() or not any(scratch.iterdir()),'ownedProcessesStopped':not processes,'ownedAppRegistrationsRemoved':not registrations,'ownedPreferencesRemoved':not unexpected and not entries(home/'Library/Preferences'),'ownedContainersRemoved':not entries(home/'Library/Containers'),'ownedApplicationScriptsRemoved':not entries(home/'Library/Application Scripts'),'ownedMountsAbsent':not mounts,'canonicalAppAndHelperAbsent':not pathlib.Path('/Applications/Wattson.app').exists() and not pathlib.Path('/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper').exists(),'canonicalSocketAbsent':not pathlib.Path('/var/run/wattson-helper.sock').exists()}
report = {'schema':1,'allPassed':all(checks.values()),'checks':checks,'details':{'processes':processes,'registrations':registrations,'preferences':entries(home/'Library/Preferences'),'containers':entries(home/'Library/Containers'),'applicationScripts':entries(home/'Library/Application Scripts'),'mounts':mounts},'finishedUTC':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
(result/'resource-audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
sys.exit(0 if report['allPassed'] else 1)
