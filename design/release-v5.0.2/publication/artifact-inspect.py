#!/usr/bin/env python3
"""Read-only artifact checks; the outer owned Bash lifecycle cleans expansion dirs."""

import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
VERSION = "5.0.2"
HELPER = "com.leoarrow.wattson.helper"
RECEIPT = "com.leoarrow.wattson.pkg"
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
CANONICAL = {
    "app_executable": Path("/Applications/Wattson.app/Contents/MacOS/Wattson"),
    "app_info": Path("/Applications/Wattson.app/Contents/Info.plist"),
    "app_code_resources": Path("/Applications/Wattson.app/Contents/_CodeSignature/CodeResources"),
    "helper": Path("/Library/PrivilegedHelperTools") / HELPER,
    "daemon": Path("/Library/LaunchDaemons") / (HELPER + ".plist"),
    "receipt_plist": Path("/var/db/receipts") / (RECEIPT + ".plist"),
    "receipt_bom": Path("/var/db/receipts") / (RECEIPT + ".bom"),
}


class InspectionError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise InspectionError(message)


def command(record, label, args, timeout=30):
    # No shell, network, new session, product launch, or retained raw tool output.
    try:
        result = subprocess.run(args, capture_output=True, timeout=timeout,
                                env={**os.environ, "LC_ALL": "C"})
    except subprocess.TimeoutExpired:
        record["commands"].append({"check": label, "timed_out": True,
                                   "timeout_seconds": timeout})
        raise InspectionError(label + " timed out") from None
    except OSError:
        raise InspectionError(label + " could not start") from None
    record["commands"].append({"check": label, "exit_code": result.returncode,
                               "timeout_seconds": timeout})
    return result


def successful(record, label, args, timeout=30):
    result = command(record, label, args, timeout)
    require(result.returncode == 0, label + " failed")
    return result


def plist(data, label):
    try:
        value = plistlib.loads(data)
    except Exception:
        raise InspectionError(label + " is not a valid plist") from None
    require(isinstance(value, dict), label + " is not a plist dictionary")
    return value


def file_hash(path):
    if not path.exists() and not path.is_symlink():
        return {"present": False}
    require(path.is_file() and not path.is_symlink(), "Expected a regular file")
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return {"present": True, "size": path.stat().st_size, "sha256": digest.hexdigest()}


def inside(path, directory):
    return path == directory or directory in path.parents


def workspace_path(argument):
    path = Path(argument).resolve()
    require(inside(path, ROOT / ".build"), "Workspace must be under project .build")
    require(any(part.endswith(".noindex") for part in path.relative_to(ROOT / ".build").parts),
            "Workspace must be under a project-local .noindex directory")
    return path


def snapshot(workspace, record):
    record["canonical_files"] = {name: file_hash(path) for name, path in CANONICAL.items()}
    if CANONICAL["app_info"].is_file():
        info = plist(CANONICAL["app_info"].read_bytes(), "Canonical App Info.plist")
        record["canonical_app_version"] = {
            key: info.get(key) for key in ("CFBundleShortVersionString", "CFBundleVersion")}

    receipt = command(record, "canonical receipt", ["/usr/sbin/pkgutil", "--pkg-info-plist", RECEIPT])
    require(receipt.returncode in (0, 1), "Canonical receipt query failed")
    record["receipt"] = {"present": receipt.returncode == 0, "version": None}
    if receipt.returncode == 0:
        record["receipt"]["version"] = plist(receipt.stdout, "Receipt query").get("pkg-version")

    processes = successful(record, "canonical process identities",
                           ["/bin/ps", "-axww", "-o", "pid=,ppid=,pgid=,comm="])
    canonical_pids = {"app": [], "helper": []}
    for line in processes.stdout.decode("utf-8", "replace").splitlines():
        fields = line.split(None, 3)
        if len(fields) != 4:
            continue
        for label, path in (("app", CANONICAL["app_executable"]), ("helper", CANONICAL["helper"])):
            if fields[3] == str(path):
                canonical_pids[label].append(int(fields[0]))
    record["canonical_running_pids"] = canonical_pids

    references = successful(record, "owned workspace process references",
                            ["/bin/ps", "-axww", "-o", "pid=,ppid=,pgid=,command="])
    workspace_processes = []
    for line in references.stdout.decode("utf-8", "replace").splitlines():
        fields = line.split(None, 3)
        if len(fields) == 4 and str(workspace) in fields[3] and int(fields[0]) != os.getpid():
            workspace_processes.append(dict(zip(("pid", "ppid", "pgid"), map(int, fields[:3]))))
    record["workspace_process_references"] = workspace_processes
    record["workspace_process_references_exclude_observer"] = True

    registrations = successful(record, "selected Wattson LaunchServices paths", [LSREGISTER, "-dump"])
    paths = set()
    for block in re.split(r"(?m)^-{5,}\s*$", registrations.stdout.decode("utf-8", "replace")):
        selected = re.search(r"(?m)^\s*identifier:\s*com\.leoarrow\.wattson\s*$", block)
        for match in re.finditer(r"(?m)^\s*path:\s*(/[^\r\n]+)\s*$", block):
            value = re.sub(r" \(0x[0-9A-Fa-f]+\)$", "", match.group(1).strip())
            if selected or value.endswith("/Wattson.app"):
                paths.add(value)
    record["selected_wattson_registered_paths"] = sorted(paths)

    images = successful(record, "owned workspace mounts", ["/usr/bin/hdiutil", "info", "-plist"])
    mounts = []
    for image in plist(images.stdout, "Disk image inventory").get("images", []):
        image_path = image.get("image-path", "")
        entities = image.get("system-entities", [])
        own_image = image_path.startswith("/") and inside(Path(image_path).resolve(), workspace)
        for entity in entities:
            mountpoint = entity.get("mount-point", "")
            if mountpoint and (own_image or inside(Path(mountpoint).resolve(), workspace)):
                mounts.append({"mount_point": mountpoint, "device": entity.get("dev-entry"),
                               "image_path": image_path if own_image else None})
    record["workspace_mount_references"] = mounts
    record["workspace_exists"] = workspace.exists()


def no_debug_entitlement(value, label):
    encoded = plistlib.dumps(value)
    require(b"com.apple.security.get-task-allow" not in encoded
            and b"com.apple.security.cs.debugger" not in encoded,
            label + " contains a debug entitlement")


def signatures(pkg, dmg, workspace, frozen, record):
    require(workspace.is_dir(), "Owned workspace is missing")
    for path in (pkg, dmg, frozen):
        require(path.is_file() and not path.is_symlink(), "Signature input must be a regular file")
    expected = plist(frozen.read_bytes(), "Frozen App entitlements")
    no_debug_entitlement(expected, "Frozen App entitlements")
    expected_bytes = plistlib.dumps(expected, fmt=plistlib.FMT_BINARY, sort_keys=True)
    record["frozen_entitlements_sha256"] = file_hash(frozen)["sha256"]
    expansion = Path(tempfile.mkdtemp(prefix="signature-expand.", dir=workspace)) / "expanded"
    record["owned_expansion"] = str(expansion.relative_to(workspace))
    successful(record, "PKG full expansion", ["/usr/sbin/pkgutil", "--expand-full", str(pkg), str(expansion)], 90)

    apps = list(expansion.rglob("*.app"))
    helpers = list(expansion.rglob(HELPER))
    daemons = list(expansion.rglob(HELPER + ".plist"))
    require(len(apps) == len(helpers) == len(daemons) == 1, "Expected exactly one App, helper, and daemon payload")
    app, helper, daemon = apps[0], helpers[0], daemons[0]
    require(app.is_dir() and not app.is_symlink()
            and app.parts[-3:] == ("Payload", "Applications", "Wattson.app"), "Unexpected App payload path")
    require(helper.parts[-4:] == ("Payload", "Library", "PrivilegedHelperTools", HELPER),
            "Unexpected helper payload path")
    require(daemon.parts[-4:] == ("Payload", "Library", "LaunchDaemons", HELPER + ".plist"),
            "Unexpected daemon payload path")
    payload = {"app_executable": app / "Contents/MacOS/Wattson", "app_info": app / "Contents/Info.plist",
               "app_code_resources": app / "Contents/_CodeSignature/CodeResources", "helper": helper, "daemon": daemon}
    record["payload_files"] = {name: file_hash(path) for name, path in payload.items()}
    require(all(item["present"] for item in record["payload_files"].values()), "A required payload file is missing")
    info = plist(payload["app_info"].read_bytes(), "Payload App Info.plist")
    require(info.get("CFBundleIdentifier") == "com.leoarrow.wattson", "Wrong payload App identifier")
    require(info.get("CFBundleShortVersionString") == info.get("CFBundleVersion") == VERSION,
            "Payload App marketing/build version must both be 5.0.2")
    record["app_versions"] = {key: info[key] for key in ("CFBundleShortVersionString", "CFBundleVersion")}

    record["code_signatures"] = {}
    for label, path in (("app", app), ("helper", helper)):
        args = ["/usr/bin/codesign", "--verify", "--all-architectures", "--strict"]
        if label == "app":
            args.append("--deep")
        successful(record, label + " all-architecture signature verification", args + [str(path)])
        architecture_proof = {}
        for architecture in ("arm64", "x86_64"):
            display = successful(record, label + " " + architecture + " signature display",
                                 ["/usr/bin/codesign", "--display", "--arch", architecture, "--verbose=4", str(path)])
            details = (display.stdout + display.stderr).decode("utf-8", "replace")
            require(re.findall(r"(?m)^Signature=(.*)$", details) == ["adhoc"], label + " slice is not ad-hoc signed")
            teams = re.findall(r"(?m)^TeamIdentifier=(.*)$", details)
            require(teams in ([], ["not set"]) and not re.search(r"(?m)^Authority=", details),
                    label + " slice has a signing authority or TeamIdentifier")
            extraction = successful(record, label + " " + architecture + " entitlements",
                                    ["/usr/bin/codesign", "--display", "--arch", architecture, "--entitlements", ":-", str(path)])
            actual = plist(extraction.stdout, label + " entitlements") if extraction.stdout.strip() else {}
            no_debug_entitlement(actual, label + " " + architecture)
            canonical = plistlib.dumps(actual, fmt=plistlib.FMT_BINARY, sort_keys=True)
            if label == "app":
                require(canonical == expected_bytes, architecture + " App entitlements differ from frozen plist")
            architecture_proof[architecture] = {"signature": "adhoc", "team_identifier": None,
                "debug_entitlements_absent": True, "entitlements_match_frozen": label == "app",
                "canonical_entitlements_sha256": hashlib.sha256(canonical).hexdigest()}
        record["code_signatures"][label] = {"all_architectures_verified": True, "slices": architecture_proof}

    package = command(record, "PKG unsigned signature display", ["/usr/sbin/pkgutil", "--check-signature", str(pkg)])
    require(package.returncode == 1 and re.search(rb"Status:\s*no signature", package.stdout + package.stderr),
            "PKG must report no signature")
    disk = command(record, "DMG unsigned signature display", ["/usr/bin/codesign", "--display", "--verbose=4", str(dmg)])
    require(disk.returncode == 1 and b"code object is not signed at all" in disk.stdout + disk.stderr,
            "DMG must report unsigned")
    record["container_signatures"] = {"pkg": "unsigned", "dmg": "unsigned"}
    record["scope"] = "Static signature supplement; frozen verify_release.sh independently proves architectures, minOS, and PKG/DMG App identity."


def main():
    require(len(sys.argv) in (4, 7), "Usage: snapshot WORKSPACE OUTPUT.json | signatures PKG DMG WORKSPACE FROZEN-ENTITLEMENTS OUTPUT.json")
    action = sys.argv[1]
    require((action == "snapshot" and len(sys.argv) == 4) or (action == "signatures" and len(sys.argv) == 7), "Invalid action or argument count")
    output = Path(sys.argv[-1]).resolve()
    require(inside(output, ROOT) and output.suffix == ".json" and not any(part.endswith(".app") for part in output.parts),
            "Evidence output must be a project JSON file outside app bundles")
    require(not output.exists(), "Evidence output already exists")
    record = {"action": action, "checked_at_utc": datetime.now(timezone.utc).isoformat(), "status": "failed", "commands": []}
    try:
        if action == "snapshot":
            snapshot(workspace_path(sys.argv[2]), record)
        else:
            signatures(Path(sys.argv[2]), Path(sys.argv[3]), workspace_path(sys.argv[4]), Path(sys.argv[5]), record)
        record["status"] = "passed"
    except InspectionError as error:
        record["error"] = str(error)
    except Exception:
        record["error"] = "Local inspection could not read or parse an expected input"
    with output.open("x") as destination:
        json.dump(record, destination, indent=2, sort_keys=True)
        destination.write("\n")
    return 0 if record["status"] == "passed" else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except InspectionError as error:
        print("artifact-inspect: " + str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("artifact-inspect: could not prepare or write local evidence", file=sys.stderr)
        sys.exit(1)
