#!/usr/bin/env python3
"""Fixed source transport and resource audit for the disposable UI benchmark."""
import gzip
import hashlib
import io
import json
import os
import pathlib
import subprocess
import sys
import tarfile
import time


def write_json(path, value):
    pathlib.Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def command(arguments):
    return subprocess.check_output(arguments, text=True, timeout=20)


def inventory(path):
    return {entry["Name"]: entry for entry in json.loads(pathlib.Path(path).read_text())}


def pack(repo, share, baseline, candidate, diagnostic_patch=""):
    repo, share = pathlib.Path(repo), pathlib.Path(share)
    manifest = {"schema": 1, "sources": {}, "archives": {}, "tools": {},
                "smokeOnly": os.environ.get("WATTSON_UI_VM_SMOKE_ONLY") == "1",
                "singleDiagnosticPass": os.environ.get("WATTSON_UI_VM_SINGLE_DIAGNOSTIC") == "1",
                "appearanceControls": os.environ.get("WATTSON_UI_VM_APPEARANCE_CONTROLS") == "1",
                "transport": {},
                "configuration": {"cold": int(os.environ.get("WATTSON_PERF_COLD_COUNT", "30")),
                                  "warm": int(os.environ.get("WATTSON_PERF_WARM_COUNT", "60")),
                                  "theme": int(os.environ.get("WATTSON_PERF_THEME_COUNT", "60")),
                                  "submission": os.environ.get("WATTSON_PERF_SUBMISSION", "forced"),
                                  "colorScheme": os.environ.get("WATTSON_PERF_COLOR_SCHEME", "dark"),
                                  "repeatBaseline": int(os.environ.get("WATTSON_PERF_REPEAT_BASELINE", "1"))},
                "pythonValidation": {"PYTHONOPTIMIZE": os.environ.get("PYTHONOPTIMIZE"), "optimize": sys.flags.optimize}}
    if manifest["singleDiagnosticPass"] and not diagnostic_patch:
        raise ValueError("Single diagnostic pass needs an explicit diagnostic patch")
    config = manifest["configuration"]
    if diagnostic_patch:
        config.update(cold=0, warm=20, theme=0)
    if any(config[key] not in range(201) for key in ("cold", "warm", "theme")) or sum(config[key] for key in ("cold", "warm", "theme")) < 1:
        raise ValueError("Invalid UI measurement counts")
    if config["submission"] not in ("forced", "natural") or config["repeatBaseline"] not in (1, 2) or config["colorScheme"] not in ("system", "light", "dark"):
        raise ValueError("Invalid UI measurement submission/repetition")
    if manifest["appearanceControls"] and (not candidate or diagnostic_patch or manifest["smokeOnly"] or manifest["singleDiagnosticPass"] or
            (config["cold"], config["warm"], config["theme"], config["submission"]) != (0, 8, 0, "natural")):
        raise ValueError("Appearance controls require baseline/candidate, natural 0/8/0, and no diagnostic/smoke mode")
    for relative in ("scripts/measure_ui_vm.sh", "tests/performance/ui-vm-guest.sh", "tests/performance/ui_vm.py"):
        manifest["transport"][relative] = hashlib.sha256((repo / relative).read_bytes()).hexdigest()
    paths = ["Core", "MenuBar", "Popover", "BatteryPowerApp.entitlements", "VERSION",
             "design/icon/in-app-logo/AppLogoColor.png", "design/icon/in-app-logo/AppLogoClearLight.png",
             "design/icon/in-app-logo/AppLogoClearDark.png"]
    if manifest["appearanceControls"]:
        paths += ["scripts/verify_interaction.sh", "tests/interaction/main.swift"]
    for label, ref in (("baseline", baseline), ("candidate", candidate)):
        if not ref:
            continue
        revision = command(["git", "-C", str(repo), "rev-parse", f"{ref}^{{commit}}"]).strip()
        archive = share / f"{label}.tar.gz"
        subprocess.run(["git", "-C", str(repo), "archive", "--format=tar.gz", "-o", str(archive), revision, "--", *paths], check=True, timeout=30)
        manifest["sources"][label] = {"revision": revision, "gitRef": ref}
        manifest["archives"][archive.name] = hashlib.sha256(archive.read_bytes()).hexdigest()
    tools = ["scripts/measure_ui_latency.sh", "tests/performance/ui-latency.swift",
             "scripts/lib/local_cleanup.sh", "scripts/lib/run_owned.py"]
    archive = share / "tools.tar.gz"
    with archive.open("wb") as output, gzip.GzipFile(fileobj=output, mode="wb", mtime=0) as compressed, tarfile.open(fileobj=compressed, mode="w") as bundle:
        for relative in tools:
            data = (repo / relative).read_bytes()
            info = tarfile.TarInfo(relative); info.size = len(data); info.mode = 0o644
            bundle.addfile(info, io.BytesIO(data))
            manifest["tools"][relative] = hashlib.sha256(data).hexdigest()
    manifest["archives"][archive.name] = hashlib.sha256(archive.read_bytes()).hexdigest()
    if diagnostic_patch:
        data = pathlib.Path(diagnostic_patch).read_bytes()
        (share / "diagnostic.patch").write_bytes(data)
        manifest["diagnosticPatchSHA256"] = hashlib.sha256(data).hexdigest()
    write_json(share / "manifest.json", manifest)


def owned_resources():
    home = pathlib.Path.home()
    prefixes = ("Wattson.UILatency.", "com.leoarrow.wattson.uilatency.",
                "Wattson.SettingsCommandInteraction.", "com.leoarrow.wattson.interactiontests.")
    def entries(relative):
        path = home / relative
        return sorted(item.name for item in path.iterdir() if item.name.startswith(prefixes)) if path.exists() else []
    return {
        "preferences": entries("Library/Preferences"),
        "containers": entries("Library/Containers"),
        "applicationScripts": entries("Library/Application Scripts"),
        "canonicalAppExists": pathlib.Path("/Applications/Wattson.app").exists(),
        "canonicalHelperExists": pathlib.Path("/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper").exists(),
        "helperSocketExists": pathlib.Path("/var/run/wattson-helper.sock").exists(),
    }


def audit():
    share = pathlib.Path("/Volumes/My Shared Files/task")
    before = json.loads((share / "results/guest-before.json").read_text())
    start = time.monotonic(); observations = []; checks = 0
    # Avoid a CFPreferences read here: observe whether delayed writes recreate a
    # just-cleared test domain after its owning process and script have exited.
    while time.monotonic() - start < 35:
        checks += 1
        current = owned_resources()
        if current != before:
            observations.append({"elapsedSeconds": round(time.monotonic() - start, 3), "resources": current})
        time.sleep(0.1)
    root = str(pathlib.Path.home() / "Project/.wattson-ui-vm.noindex")
    processes = [line.strip() for line in command(["/bin/ps", "-axo", "pid=,comm="]).splitlines() if root + "/" in line]
    registrar = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    registrations = [line.strip() for line in command([registrar, "-dump"]).splitlines() if root + "/" in line]
    scratch = pathlib.Path(root)
    assertions = {
        "resourcesPreserved": owned_resources() == before,
        "delayedPreferenceWritesAbsent": not observations,
        "ownedProcessesStopped": not processes,
        "ownedAppRegistrationsRemoved": not registrations,
        "guestLocalScratchRemoved": not scratch.exists() or not any(scratch.iterdir()),
    }
    report = {"schema": 1, "allPassed": all(assertions.values()), "checks": assertions,
              "filesystemObservationSeconds": round(time.monotonic() - start, 3), "filesystemChecks": checks,
              "unexpectedResourceObservations": observations, "processes": processes, "registrations": registrations,
              "preferencesMethod": "filesystem-only; no defaults or CFPreferences read",
              "before": before, "after": owned_resources()}
    write_json(share / "results/guest-cleanup-audit.json", report)
    print(json.dumps(report, sort_keys=True))
    return 0 if report["allPassed"] else 1


def verify_result(path, diagnostic, variant_comparison=False):
    rows = [json.loads(line) for line in pathlib.Path(path).read_text().splitlines()]
    environment = [row for row in rows if row["type"] == "environment"]
    if len(environment) != 1 or rows[-1]["type"] != "complete" or any(row["type"] == "failure" for row in rows):
        raise RuntimeError("UI measurement did not complete")
    if diagnostic:
        traces = [row for row in rows if row["type"] == "open_attribution"]
        samples = [row for row in rows if row["type"] == "sample"]
        modes = {"classic", "glass_regular", "glass_clear"}
        if environment[0].get("diagnostic_only") is not True or {row["mode"] for row in traces} != modes:
            raise RuntimeError("Diagnostic metadata/traces missing; refusing a silent uninstrumented run")
        if not samples or {row["case"] for row in samples} != {"popup_reopen_warm"} or {row["mode"] for row in samples} != modes:
            raise RuntimeError("Diagnostic must execute only warm opens in all three hosts")
    if variant_comparison:
        expected_variants = set(environment[0].get("diagnostic_variants", []))
        if expected_variants not in ({"original", "foreground_first"}, {"original", "early_window_first"}):
            raise RuntimeError("Assembly comparison variant metadata missing")
        for variant in expected_variants:
            for mode in ("classic", "glass_regular", "glass_clear"):
                measured = [row for row in traces if row.get("variant") == variant and row["mode"] == mode and not row["warmup"]]
                if len(measured) != 20:
                    raise RuntimeError(f"Assembly comparison needs 20 traces for {variant}/{mode}")
    print(json.dumps({"allPassed": True, "diagnostic": diagnostic, "variantComparison": variant_comparison,
                      "sampleRows": sum(row["type"] == "sample" for row in rows)}, sort_keys=True))


def main():
    mode, *args = sys.argv[1:]
    if mode == "pack":
        pack(*args)
    elif mode == "before":
        print(json.dumps(owned_resources(), sort_keys=True))
    elif mode == "audit":
        return audit()
    elif mode == "verify-result":
        verify_result(args[0], args[1] == "1", len(args) > 2 and args[2] == "1")
    else:
        name, path, *rest = args; before = inventory(path)
        if mode == "preflight":
            if name in before:
                raise RuntimeError("Owned clone already exists; refusing reuse")
            if not all(before[n]["State"] == "stopped" for n in ("macOS-TestLab", "macOS-TestLab-Base")):
                raise RuntimeError("TestLab/Base is in use")
        elif mode == "state":
            print(before[name]["State"] if name in before else "missing")
        elif mode == "after":
            after = inventory(rest[0])
            if name in after or not set(before) <= set(after):
                raise RuntimeError("Owned clone deletion/inventory check failed")
            preserved = {n: v["State"] == after[n]["State"] and v["Running"] == after[n]["Running"] for n, v in before.items()}
            if not all(preserved.values()):
                raise RuntimeError("Unrelated VM state changed; never repair it automatically")
            print(json.dumps({"ownedVM": name, "ownedCloneRemoved": True, "otherVMStatesPreserved": preserved}, sort_keys=True))
        else:
            raise ValueError("Unknown mode")
    return 0


if __name__ == "__main__":
    sys.exit(main())
