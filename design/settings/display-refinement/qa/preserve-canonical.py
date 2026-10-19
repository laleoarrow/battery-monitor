#!/usr/bin/env python3
"""Hash production settings and installed bytes without contacting the helper."""
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys


def snapshot():
    app = pathlib.Path('/Applications/Wattson.app')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    paths = [app / 'Contents/MacOS/Wattson',
             pathlib.Path('/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper'),
             pathlib.Path('/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist')]
    preferences = [pathlib.Path.home() / 'Library/Preferences/com.leoarrow.wattson.plist',
                   pathlib.Path.home() / 'Library/Containers/com.leoarrow.wattson/Data/Library/Preferences/com.leoarrow.wattson.plist']
    settings = {}
    for path in preferences:
        if path.is_file():
            values = plistlib.loads(path.read_bytes())
            settings[str(path)] = {key: hashlib.sha256(plistlib.dumps(value, fmt=plistlib.FMT_BINARY)).hexdigest()
                                   for key, value in values.items() if not key.startswith('NS')}
    processes = subprocess.check_output(['/bin/ps', '-axww', '-o', 'pid=,command='], text=True, timeout=15)
    commands = [line.strip() for line in processes.splitlines() if '/Applications/Wattson.app/Contents/MacOS/Wattson' in line]
    assert commands, 'Canonical Wattson was not running'
    return {'version': info['CFBundleShortVersionString'], 'processes': commands,
            'files': {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths},
            'settings': settings, 'helperContacted': False, 'rawSettingsValuesLogged': False}


mode = sys.argv[1]
actual = snapshot()
if mode == 'record':
    pathlib.Path(sys.argv[2]).write_text(json.dumps(actual, indent=2) + '\n')
elif mode == 'verify':
    expected = json.loads(pathlib.Path(sys.argv[2]).read_text())
    checks = {key: expected[key] == actual[key] for key in ('version', 'processes', 'files', 'settings')}
    report = {'allPassed': all(checks.values()), 'checks': checks,
              'settingsCompared': sum(len(values) for values in actual['settings'].values()), 'current': actual}
    pathlib.Path(sys.argv[3]).write_text(json.dumps(report, indent=2) + '\n')
    assert report['allPassed'], checks
else:
    raise ValueError('Unknown mode')
