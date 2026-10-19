#!/usr/bin/env python3
"""Inspect only the disposable guest after the owned build/capture script exits."""
import json
import pathlib
import subprocess
import sys
import time

home = pathlib.Path.home()
scratch = home / 'Project/.display-settings.noindex'
result = pathlib.Path(sys.argv[1])
prefixes = ('com.leoarrow.wattson.displayqa.', 'Wattson.TestRuntime.')


def entries(directory):
    return sorted(str(path.relative_to(home)) for path in directory.iterdir() if path.name.startswith(prefixes)) if directory.exists() else []


def output(arguments):
    return subprocess.check_output(arguments, text=True, timeout=20)


started = time.monotonic()
unexpected = []
count = 0
while time.monotonic() - started < 35:
    count += 1
    preferences = entries(home / 'Library/Preferences')
    if preferences:
        unexpected.append({'elapsed': round(time.monotonic() - started, 3), 'preferences': preferences})
    time.sleep(.1)
(result / 'preferences-observation.json').write_text(json.dumps({
    'durationSeconds': round(time.monotonic() - started, 3), 'filesystemChecks': count,
    'unexpectedPreferences': unexpected, 'allPassed': not unexpected,
    'method': 'Filesystem-only observation after exact-suite cleanup; no defaults reads.',
}, indent=2) + '\n')
processes = [line.strip() for line in output(['/bin/ps', '-axww', '-o', 'pid=,command=']).splitlines()
             if '/Project/.display-settings.noindex/' in line]
registrar = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
registrations = [line.strip() for line in output([registrar, '-dump']).splitlines()
                 if '/Project/.display-settings.noindex/' in line]
mounts = [line for line in output(['/sbin/mount']).splitlines() if '/Project/.display-settings.noindex/' in line]
checks = {
    'sourceAndBuildScratchRemoved': not scratch.exists() or not any(scratch.iterdir()),
    'ownedProcessesStopped': not processes, 'ownedAppRegistrationsRemoved': not registrations,
    'ownedPreferencesRemoved': not unexpected and not entries(home / 'Library/Preferences'),
    'ownedContainersRemoved': not entries(home / 'Library/Containers'),
    'ownedApplicationScriptsRemoved': not entries(home / 'Library/Application Scripts'),
    'ownedMountsAbsent': not mounts,
    'canonicalAppAndHelperAbsent': not pathlib.Path('/Applications/Wattson.app').exists()
        and not pathlib.Path('/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper').exists(),
    'canonicalSocketAbsent': not pathlib.Path('/var/run/wattson-helper.sock').exists(),
}
report = {'schema': 1, 'allPassed': all(checks.values()), 'checks': checks,
          'details': {'processes': processes, 'registrations': registrations, 'mounts': mounts},
          'finishedUTC': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
(result / 'resource-audit.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
sys.exit(0 if report['allPassed'] else 1)
