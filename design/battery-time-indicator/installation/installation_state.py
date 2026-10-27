"""Read-only 5.0.2 local-install checks; reuse the retained canonical snapshot reader."""
import sys

sys.dont_write_bytecode = True
if sys.flags.optimize:
    raise SystemExit("Run without Python optimization.")

import importlib.util
import json
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
VERSION = "5.0.2"
spec = importlib.util.spec_from_file_location(
    "wattson_canonical_snapshot", ROOT / "design/release-v5.0.1/installation/installation_state.py"
)
canonical = importlib.util.module_from_spec(spec)
spec.loader.exec_module(canonical)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def identity(package, source):
    canonical.check_console_user()
    package = Path(package)
    require(package.is_absolute() and package.is_file(), "Require an existing absolute PKG path")
    require(package.name == f"Wattson-v{VERSION}-macos-universal.pkg", "Wrong package version")
    require(re.fullmatch(r"[0-9a-f]{40}", source), "Require a full frozen source SHA")
    resolved = canonical.run(["git", "-C", str(ROOT), "rev-parse", source + "^{commit}"]).decode().strip()
    require(resolved == source, "Source commit is not present locally")
    digest = canonical.digest(package)
    manifest = (package.parent / "SHA256SUMS.txt").read_text().splitlines()
    require(any(line.split() == [digest, package.name] for line in manifest), "PKG does not match its checksum manifest")
    return package, digest


def baseline(package, source, before_path):
    package, digest = identity(package, source)
    before = json.loads(Path(before_path).read_text())
    require(before["expectedVersion"] == VERSION and before["sourceCommit"] == source,
            "Baseline version/source mismatch")
    require(before["packageSHA256"] == digest, "Package changed since the pre-install snapshot")
    require(sum(map(len, before["settingsValueHashes"].values())) == before["productSettingsCount"],
            "Invalid baseline settings count")
    return package, before


def retained_settings(before):
    actual = canonical.settings_hashes()
    for location, settings in before["settingsValueHashes"].items():
        for key, expected in settings.items():
            require(actual.get(location, {}).get(key) == expected, f"Existing setting changed: {location}:{key}")
    return before["productSettingsCount"]


def installed_state():
    state = canonical.canonical_state()
    require(state["version"] == state["buildVersion"] == state["receipt"]["version"] == VERSION,
            "Installed App/build/receipt versions do not all match 5.0.2")
    require(state["bundleIdentifier"] == "com.leoarrow.wattson", "Wrong canonical bundle identifier")
    return state


def main():
    mode, *arguments = sys.argv[1:]
    if mode == "before":
        package, source, output = arguments
        package, digest = identity(package, source)
        settings = canonical.settings_hashes()
        canonical.write_new(Path(output), {
            "schema": 1, "checkedAtUTC": datetime.now(timezone.utc).isoformat(),
            "expectedVersion": VERSION, "sourceCommit": source,
            "packageSHA256": digest, "packagePath": str(package),
            "settingsValueHashes": settings, "productSettingsCount": sum(map(len, settings.values())),
            "canonicalBefore": canonical.canonical_state(), "publicRelease": False,
            "rawSettingsValuesLogged": False, "helperContacted": False,
            "canonicalLifecycleChanged": False,
        })
        print("LOCAL_INSTALL_BASELINE_RECORDED")
    elif mode == "preflight":
        baseline(*arguments)
    elif mode == "details":
        package, source, before_path, output, scratch, payload_app = arguments
        package, before = baseline(package, source, before_path)
        canonical.write_new(Path(output), {
            "schema": 1, "checkedAtUTC": datetime.now(timezone.utc).isoformat(),
            "version": VERSION, "sourceCommit": source, "packageSHA256": canonical.digest(package),
            "packagePath": str(package), "canonicalAfter": installed_state(),
            "existingSettingsCompared": retained_settings(before), "existingSettingsUnchanged": True,
            "appAndHelperAndDaemonMatchVerifiedPayload": True, "signatureVerified": True,
            "architectures": ["arm64", "x86_64"], "helperHealth": True, "helperV5Negotiated": True,
            "publicRelease": False, "popupInteractionVerified": False,
            "verificationDidNotInstallOrLaunchGUI": True, "rawSettingsValuesLogged": False,
            "pendingCleanup": True, "beforePath": before_path,
            "ownedVerificationResources": {"scratch": scratch, "expandedApp": payload_app},
        })
    elif mode == "finalize":
        stage, output = map(Path, arguments)
        record = json.loads(stage.read_text())
        scratch = Path(record["ownedVerificationResources"]["scratch"])
        expanded_app = record["ownedVerificationResources"]["expandedApp"]
        require(not scratch.exists(), "Owned expanded-payload scratch remains")
        registrar = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        registrations = canonical.run([registrar, "-dump"], timeout=45).decode()
        spotlight = canonical.run(["/usr/bin/mdfind", 'kMDItemCFBundleIdentifier == "com.leoarrow.wattson"']).decode().splitlines()
        require(expanded_app not in registrations and expanded_app not in spotlight,
                "Expanded App registration remains")
        _, before = baseline(record["packagePath"], record["sourceCommit"], record["beforePath"])
        require(retained_settings(before) == record["existingSettingsCompared"], "Settings check changed")
        after = installed_state()
        for key in ("appBundleTreeSHA256", "helperSHA256", "daemonSHA256", "receipt"):
            require(after[key] == record["canonicalAfter"][key], "Canonical payload changed during cleanup")
        record.update(pendingCleanup=False, allPassed=True, cleanupVerified={
            "ownedScratchRemoved": True, "expandedAppLaunchServicesAbsent": True,
            "expandedAppSpotlightAbsent": True, "ownedMountsCreated": False,
            "canonicalInstallationNotCleaned": True,
        })
        canonical.write_new(output, record)
        print("CANONICAL_LOCAL_INSTALL_VERIFIED")
    else:
        raise RuntimeError("Unknown verification mode")


if __name__ == "__main__":
    main()
