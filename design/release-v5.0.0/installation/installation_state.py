"""Read-only canonical snapshot; product values stay in memory and are hashed."""
import os
import sys

os.environ.pop("PYTHONOPTIMIZE", None)
sys.dont_write_bytecode = True
if sys.flags.optimize:
    raise SystemExit("Optimized Python is unsupported; unset PYTHONOPTIMIZE and do not pass -O.")

import argparse
import hashlib
import json
import plistlib
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

VERSION = '5.0.0'
APP = Path('/Applications/Wattson.app')
HELPER = Path('/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper')
DAEMON = Path('/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist')
RECEIPT = 'com.leoarrow.wattson.pkg'
REQUIRED_SETTINGS = {
    'appearance.liquidGlassStyle', 'popover.topProcessesCompact', 'popover.module.flow',
    'popover.module.history', 'popover.module.topProcesses', 'appearance.showPopoverArrow',
    'appearance.inAppLogoStyle', 'popover.module.lanes', 'popover.topProcessCount',
    'appearance.liquidGlassEnabled', 'appearance.colorScheme', 'menubar.showsPercentage',
    'menubar.iconStyle', 'popover.moduleOrder', 'appearance.liquidGlassTransparency',
    'popover.ringMetrics',
}
PREFERENCES = {
    '0': Path.home() / 'Library/Containers/com.leoarrow.wattson/Data/Library/Preferences/com.leoarrow.wattson.plist',
    '1': Path.home() / 'Library/Preferences/com.leoarrow.wattson.plist',
}


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def run(arguments, timeout=15):
    return subprocess.run(arguments, capture_output=True, check=True,
                          timeout=timeout).stdout


def check_console_user():
    assert os.getuid() != 0 and os.stat('/dev/console').st_uid == os.getuid(), 'Run as console user'


def settings_hashes():
    hashes = {}
    for index, path in PREFERENCES.items():
        if path.exists():
            values = plistlib.loads(path.read_bytes())
            selected = {key: hashlib.sha256(plistlib.dumps(value, fmt=plistlib.FMT_BINARY)).hexdigest()
                        for key, value in values.items()
                        if key.startswith(('appearance.', 'popover.', 'menubar.', 'updates.'))}
            if selected:
                hashes[index] = selected
    assert REQUIRED_SETTINGS <= {key for values in hashes.values() for key in values}, 'Missing retained product settings'
    return hashes


def canonical_state():
    info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    receipt = plistlib.loads(run(['/usr/sbin/pkgutil', '--pkg-info-plist', RECEIPT]))
    processes = run(['/bin/ps', '-axo', 'pid=,comm=']).decode().splitlines()
    pids = [int(parts[0]) for line in processes if len(parts := line.strip().split(None, 1)) == 2
            and parts[1] == str(APP / 'Contents/MacOS/Wattson')]
    tree = []
    for path in sorted(APP.rglob('*')):
        relative = str(path.relative_to(APP))
        if path.is_symlink():
            tree.append([relative, 'symlink', os.readlink(path)])
        elif path.is_file():
            tree.append([relative, 'file', path.stat().st_mode & 0o7777, digest(path)])
    return {
        'version': info['CFBundleShortVersionString'], 'buildVersion': info['CFBundleVersion'],
        'bundleIdentifier': info['CFBundleIdentifier'], 'canonicalAppPIDs': pids,
        'appExecutableSHA256': digest(APP / 'Contents/MacOS/Wattson'),
        'appInfoPlistSHA256': digest(APP / 'Contents/Info.plist'),
        'appBundleTreeSHA256': hashlib.sha256(json.dumps(tree, separators=(',', ':')).encode()).hexdigest(),
        'appBundleFilesOrSymlinks': len(tree), 'helperSHA256': digest(HELPER),
        'daemonSHA256': digest(DAEMON),
        'receipt': {'identifier': receipt['pkgid'], 'version': receipt['pkg-version'],
                    'installTime': receipt.get('install-time')},
    }


def write_new(path, value):
    with path.open('x') as destination:
        destination.write(json.dumps(value, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_commit')
    parser.add_argument('--output', type=Path, default=Path(__file__).parent / 'before.json')
    arguments = parser.parse_args()
    assert re.fullmatch('[0-9a-f]{40}', arguments.source_commit), 'Require full source SHA'
    check_console_user()
    settings = settings_hashes()
    state = canonical_state()
    write_new(arguments.output, {
        'schema': 1, 'checkedAtUTC': datetime.now(timezone.utc).isoformat(),
        'expectedVersion': VERSION, 'sourceCommit': arguments.source_commit,
        'settingsValueHashes': settings,
        'productSettingsCount': sum(map(len, settings.values())),
        'requiredSettingsCount': len(REQUIRED_SETTINGS), 'canonicalBefore': state,
        'rawSettingsValuesLogged': False, 'helperContacted': False,
        'canonicalLifecycleChanged': False,
    })
    print(json.dumps({'beforeCollected': True, 'canonicalVersion': state['version'],
                      'canonicalPIDs': state['canonicalAppPIDs'],
                      'settingsHashed': sum(map(len, settings.values())),
                      'helperContacted': False, 'canonicalLifecycleChanged': False}))
