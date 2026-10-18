"""Read-only preservation check; never contact or mutate the production helper."""
import hashlib
import json
import plistlib
import subprocess
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parents[3]
before = json.loads((root / 'design/release-v4.3.22/publication/before.json').read_text())
preference_paths = {
    '0': Path.home() / 'Library/Containers/com.leoarrow.wattson/Data/Library/Preferences/com.leoarrow.wattson.plist',
    '1': Path.home() / 'Library/Preferences/com.leoarrow.wattson.plist',
}
matched_settings = 0
for index, expected in before['settingsValueHashes'].items():
    actual = plistlib.loads(preference_paths[index].read_bytes())
    for key, expected_hash in expected.items():
        assert key in actual
        digest = hashlib.sha256(plistlib.dumps(actual[key], fmt=plistlib.FMT_BINARY)).hexdigest()
        assert digest == expected_hash, 'An existing setting changed'
        matched_settings += 1

app = Path('/Applications/Wattson.app')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
command = subprocess.run(['/bin/ps', '-p', '80435', '-o', 'comm='],
                         capture_output=True, text=True, check=True, timeout=10).stdout.strip()
assert command == str(app / 'Contents/MacOS/Wattson')
owned_prefixes = ['activity-image-baseline.', 'activity-focused.', 'hardening-swift.']
remaining_builds = [str(path.relative_to(root)) for path in (root / '.build').iterdir()
                    if any(path.name.startswith(prefix) for prefix in owned_prefixes)]
assert not remaining_builds
release_log = (Path(__file__).parent / 'universal-build.log').read_text()
release_line = next(line for line in release_log.splitlines() if line.startswith('Built universal app: '))
built_app = Path(release_line.removeprefix('Built universal app: '))
assert not built_app.parent.exists(), 'Owned universal build was not cleaned'

registrar = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
registrations = subprocess.run([registrar, '-dump'], capture_output=True, text=True,
                               check=True, timeout=30).stdout
assert str(built_app) not in registrations
spotlight = subprocess.run(['/usr/bin/mdfind', 'kMDItemCFBundleIdentifier == "com.leoarrow.wattson"'],
                          capture_output=True, text=True, check=True, timeout=30).stdout.splitlines()
assert str(built_app) not in spotlight

record = {
    'checkedAtUTC': datetime.now(timezone.utc).isoformat(),
    'canonicalVersion': info['CFBundleShortVersionString'],
    'canonicalPIDUnchanged': True,
    'existingSettingsCompared': matched_settings,
    'existingSettingsUnchanged': True,
    'ownedHostBuildScratchRemaining': remaining_builds,
    'ownedUniversalBuildRemoved': True,
    'ownedUniversalAppLaunchServicesRegistrationAbsent': True,
    'ownedUniversalAppSpotlightEntryAbsent': True,
    'helperContacted': False,
    'rawSettingsValuesLogged': False,
}
print(json.dumps(record, indent=2))
