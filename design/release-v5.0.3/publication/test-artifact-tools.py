#!/usr/bin/env python3
"""Offline identity/byte-contract regressions; never contacts GitHub or the app."""
import ast
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
from unittest.mock import patch
import zipfile

HERE = Path(__file__).resolve().parent
SHA = "a" * 40
RUN, HEADLESS = 101, 102
PASSED = []
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE.parents[2] / "tests"))
from local_runtime import TemporaryDirectory as ManagedTemporaryDirectory, run as runtime_run


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check(name, function, rejected=False):
    with contextlib.redirect_stdout(io.StringIO()):
        try:
            function()
        except (RuntimeError, ValueError):
            if not rejected:
                raise
        else:
            if rejected:
                raise AssertionError(name + " unexpectedly accepted")
    PASSED.append(name)


def contents(transfer):
    files = {
        "Wattson-v5.0.3-macos-universal.pkg": b"fixture package",
        "Wattson-v5.0.3-macos-universal.dmg": b"fixture disk image",
        "Wattson-v5.0.3-release-info.txt":
            "".join(k + "=" + v + "\n" for k, v in transfer.METADATA.items()).encode(),
    }
    files["SHA256SUMS.txt"] = "".join(
        hashlib.sha256(data).hexdigest() + "  " + name + "\n"
        for name, data in files.items()).encode()
    return files


def main(runtime_root):
    transfer, proof, public = (load("artifact-" + suffix)
                               for suffix in ("transfer", "proof", "public-download"))
    for path in HERE.iterdir():
        if path.suffix == ".py":
            ast.parse(path.read_text(), filename=str(path))
        elif path.suffix == ".sh":
            runtime_run(["/bin/bash", "-n", str(path)], check=True)
    PASSED.append("all_verification_tools_parse")
    install_spec = importlib.util.spec_from_file_location(
        "public_install_version_fixture", HERE.parent / "installation/installation_state.py")
    install = importlib.util.module_from_spec(install_spec)
    install_spec.loader.exec_module(install)
    assert install.VERSION == install.local.VERSION == "5.0.3"
    for version, accepted in (("5.0.3", True), ("5.0.2", False)):
        state = dict(version=version, buildVersion=version, receipt=dict(version=version),
                     bundleIdentifier="com.leoarrow.wattson")
        with patch.object(install.local.canonical, "canonical_state", return_value=state):
            check("installed_version_" + ("accepts_" if accepted else "rejects_") + version,
                  install.local.installed_state, not accepted)
    for script, args in (
            ("artifact-verify.sh", []),
            ("artifact-verify.sh", ["101", "bad-sha", "102"]),
            ("artifact-public-verify.sh", ["101", "bad-sha"]),
            ("artifact-public-curl-retry.sh", ["101", "bad-sha"]),
            ("tap-sync.sh", ["bad-digest", SHA, "101"])):
        result = runtime_run(["/bin/bash", str(HERE / script), *args],
                             capture_output=True, timeout=5, cleanup_grace=65)
        assert result.returncode == 2
    PASSED.append("shell_rejects_missing_or_malformed_identity_before_scratch")
    result = runtime_run(
        [sys.executable, str(HERE / "verify-public-artwork.py"),
         "--source-sha", "bad-sha", "--source-only"], capture_output=True, timeout=5)
    assert result.returncode == 1 and b"Explicit full frozen source SHA required" in result.stderr
    PASSED.append("gallery_rejects_malformed_source_before_git_or_network")
    gallery = load("verify-public-artwork")

    def gallery_case(kind="valid"):
        files, sources = {"index.html": b"<html>Fixture</html>"}, {"VERSION": b"5.0.3\n"}
        manifest = dict(version="5.0.3", runtimeScreenshotsIncluded=False,
                        svgSources=[], sourcePackages=[], previews=[])
        for family, count in gallery.SVG_FAMILIES.items():
            name = f"Wattson-v5.0.3-{family.title()}-SVG.zip"
            archive = io.BytesIO()
            with zipfile.ZipFile(archive, "w") as zipped:
                for index in range(count):
                    leaf = f"{family}-{index}.svg"
                    path, source = f"svg/{family}/{leaf}", f"design/fixture/{leaf}"
                    data = f"<svg>{family}-{index}</svg>".encode()
                    files[path] = sources[source] = data
                    manifest["svgSources"].append(dict(copy=path, source=source))
                    zipped.writestr(name.removesuffix(".zip") + "/" + leaf,
                                    b"changed" if kind == "zip_master" and family == "power" and index == 0 else data)
            files[name] = archive.getvalue()
            manifest["sourcePackages"].append(dict(path=name, sha256=gallery.digest(files[name]), runtimeMasterCount=count))
        for path in gallery.PREVIEW_PATHS:
            source = "design/fixture/" + Path(path).name
            files[path] = sources[source] = b"fixture PNG " + path.encode()
            entry = dict(path=path, source=source, sha256=gallery.digest(files[path]), bytes=len(files[path]))
            if "time-source" in path:
                sources[source] = b"fixture vector " + path.encode()
                entry["sourceSha256"] = gallery.digest(sources[source])
                if kind == "preview_source":
                    entry["sourceSha256"] = "0" * 64
            manifest["previews"].append(entry)
        if kind == "duplicate_master":
            manifest["svgSources"].append(manifest["svgSources"][0])
        files["manifest.json"] = json.dumps(manifest).encode()
        manifest_files = dict(files)
        if kind == "missing_checksum":
            manifest_files.pop("index.html")
        files["SHA256SUMS.txt"] = "".join(
            gallery.digest(data) + "  " + name + "\n" for name, data in manifest_files.items()).encode()
        sources.update({gallery.SOURCE + name: data for name, data in files.items()})
        tree = "".join(gallery.SOURCE + name + "\n" for name in files).encode()
        with patch.object(gallery, "frozen_bytes", side_effect=lambda path: sources[path]), \
                patch.object(gallery.subprocess, "check_output", return_value=tree):
            frozen_files, _, frozen_manifest = gallery.load_frozen()
            gallery.validate_zip_masters(frozen_files, frozen_manifest)

    check("gallery_accepts_full_tree_twenty_masters_and_preview_sources", gallery_case)
    for kind in ("missing_checksum", "zip_master", "duplicate_master", "preview_source"):
        check("gallery_rejects_" + kind, lambda k=kind: gallery_case(k), True)
    with tempfile.TemporaryDirectory(prefix=".artifact-checks-", suffix=".noindex",
                                     dir=runtime_root) as temporary:
        scratch = Path(temporary)
        tap_script = (HERE / "tap-sync.sh").read_text()
        tap_updater = tap_script.split('"$checkout/Casks/wattson.rb" "$PKG_SHA" <<\'PY\'\n', 1)[1].split("\nPY\n", 1)[0]
        for old_version, accepted in (("5.0.2", True), ("5.0.3", False), ("4.3.23", False)):
            cask = scratch / "wattson.rb"
            original = 'cask "wattson" do\n  version "' + old_version + '"\n  sha256 "' + "0" * 64 + '"\nend\n'
            cask.write_text(original)
            result = runtime_run([sys.executable, "-c", tap_updater, str(cask), "1" * 64],
                                 capture_output=True, timeout=5)
            assert (result.returncode == 0) == accepted
            expected = original.replace('version "5.0.2"', 'version "5.0.3"').replace("0" * 64, "1" * 64)
            assert cask.read_text() == (expected if accepted else original)
            PASSED.append("tap_update_" + ("accepts_" if accepted else "rejects_") + old_version)
        transfer.RUN, transfer.SHA, transfer.HEADLESS_RUN = RUN, SHA, HEADLESS
        transfer.save = lambda *args: None
        candidate = dict(id=RUN, head_sha=SHA, head_branch="main",
                         path=".github/workflows/macos-helper-install.yml",
                         event="workflow_dispatch", run_attempt=1,
                         status="completed", conclusion="success")
        headless = dict(candidate, id=HEADLESS, path=".github/workflows/ci.yml", event="push")
        jobs = [dict(name=name, status="completed", conclusion="success")
                for name in transfer.EXPECTED_JOBS]
        artifact = dict(id=201, name=transfer.NAME, expired=False,
                        workflow_run=dict(id=RUN, head_sha=SHA, head_branch="main"),
                        digest="sha256:" + "b" * 64, size_in_bytes=1)
        metadata = {
            f"actions/runs/{RUN}": candidate,
            f"actions/runs/{HEADLESS}": headless,
            "git/ref/heads/main": {"object": {"sha": SHA}},
            f"actions/runs/{RUN}/jobs?per_page=100": {"jobs": jobs, "total_count": 6},
            f"actions/runs/{RUN}/artifacts?per_page=100":
                {"artifacts": [artifact], "total_count": 1},
        }

        def readiness(change=None):
            fixture = copy.deepcopy(metadata)
            if change:
                change(fixture)
            transfer.api = lambda endpoint: fixture[endpoint]
            return transfer.ready(scratch)

        check("readiness_accepts_exact_completed_source", readiness)
        changes = {
            "wrong_source": lambda d: d[f"actions/runs/{RUN}"].update(head_sha="c" * 40),
            "failed_candidate": lambda d: d[f"actions/runs/{RUN}"].update(conclusion="failure"),
            "rerun_attempt": lambda d: d[f"actions/runs/{RUN}"].update(run_attempt=2),
            "moved_main": lambda d: d["git/ref/heads/main"]["object"].update(sha="c" * 40),
            "dispatch_headless": lambda d: d[f"actions/runs/{HEADLESS}"].update(event="workflow_dispatch"),
            "failed_install": lambda d: d[f"actions/runs/{RUN}/jobs?per_page=100"]["jobs"][0].update(conclusion="failure"),
            "expired_artifact": lambda d: d[f"actions/runs/{RUN}/artifacts?per_page=100"]["artifacts"][0].update(expired=True),
            "wrong_artifact_source": lambda d: d[f"actions/runs/{RUN}/artifacts?per_page=100"]["artifacts"][0]["workflow_run"].update(head_sha="c" * 40),
        }
        for name, change in changes.items():
            check("readiness_rejects_" + name, lambda c=change: readiness(c), True)
        with contextlib.redirect_stdout(io.StringIO()):
            assert readiness(lambda d: d[f"actions/runs/{RUN}"].update(status="in_progress")) == 3
        PASSED.append("pending_candidate_returns_without_download")

        def archive_case(kind="valid"):
            with tempfile.TemporaryDirectory(dir=scratch) as directory:
                work = Path(directory)
                files = contents(transfer)
                if kind == "manifest_duplicate":
                    files["SHA256SUMS.txt"] += files["SHA256SUMS.txt"].splitlines(True)[0]
                elif kind == "metadata_wrong":
                    files["Wattson-v5.0.3-release-info.txt"] = b"version=4.0.0\n"
                    files["SHA256SUMS.txt"] = "".join(
                        hashlib.sha256(data).hexdigest() + "  " + name + "\n"
                        for name, data in files.items() if name != "SHA256SUMS.txt").encode()
                elif kind == "manifest_mismatch":
                    files["Wattson-v5.0.3-macos-universal.pkg"] += b"changed"
                archive = io.BytesIO()
                with zipfile.ZipFile(archive, "w") as zipped:
                    for name, data in files.items():
                        entry = zipfile.ZipInfo(name)
                        if kind == "symlink" and name.endswith(".pkg"):
                            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                        zipped.writestr(entry, data)
                    if kind == "extra_member":
                        zipped.writestr("../escape", b"bad")
                payload = archive.getvalue()
                binding = dict(artifact, size_in_bytes=len(payload),
                               digest="sha256:" + hashlib.sha256(payload).hexdigest())
                if kind == "digest_mismatch":
                    binding["digest"] = "sha256:" + "0" * 64
                (work / "artifact.json").write_text(json.dumps(binding))

                def fake_run(args, *unused, **kwargs):
                    if args[1:3] == ["auth", "token"]:
                        return b"offline-fixture-token"
                    headers = Path(args[args.index("--dump-header") + 1])
                    if "--range" not in args:
                        headers.write_text("HTTP/1.1 302 Found\nLocation: https://example.invalid/fixture\n")
                    else:
                        begin, end = map(int, args[args.index("--range") + 1].split("-"))
                        headers.write_text(f"HTTP/1.1 206 Partial Content\nContent-Range: bytes {begin}-{end}/{len(payload)}\n")
                        Path(args[args.index("--output") + 1]).write_bytes(payload[begin:end + 1])
                    return b""

                transfer.run = fake_run
                transfer.download(work)

        check("archive_accepts_exact_bytes_manifest_metadata", archive_case)
        for kind in ("manifest_duplicate", "metadata_wrong", "manifest_mismatch",
                     "symlink", "extra_member", "digest_mismatch"):
            check("archive_rejects_" + kind, lambda k=kind: archive_case(k), True)

        def provenance_case(kind="valid"):
            with tempfile.TemporaryDirectory(dir=scratch) as directory:
                root = Path(directory)
                evidence = root / "design/release-v5.0.3/publication"
                record = evidence / f"artifact-{RUN}-review.fixture"
                record.mkdir(parents=True)
                final = root / "dist" / f"github-candidate-v5.0.3-{RUN}"
                final.mkdir(parents=True)
                files = contents(transfer)
                expected = {}
                for name, data in files.items():
                    (final / name).write_bytes(data)
                    expected[name] = dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
                state = dict(status="passed", canonical_files={"app": "fixed"}, receipt={"version": "4.3.24"})
                for name, value in (
                        ("before", state), ("after", state),
                        ("signatures", {"status": "passed"}),
                        ("download", dict(run_id=RUN, source_sha=SHA, files=expected))):
                    (record / f"artifact-{name}.json").write_text(json.dumps(value))
                if kind == "canonical_changed":
                    (record / "artifact-after.json").write_text(json.dumps(dict(state, canonical_files={})))
                (record / "artifact-workspace.txt").write_text(str(root / "already-cleaned"))
                proof.ROOT, proof.__file__ = root, str(evidence / "artifact-proof.py")
                public.ROOT, public.EVIDENCE = root, evidence
                with patch.dict(os.environ, {"WATTSON_RELEASE_SOURCE_SHA": SHA,
                                             "WATTSON_RELEASE_CANDIDATE_RUN_ID": str(RUN)}):
                    with patch.object(sys, "argv", ["proof", str(record), str(final), str(RUN)]):
                        proof.main()
                    if kind == "proof_only":
                        return
                    assets = [dict(name=name, digest="sha256:" + item["sha256"],
                                   size=item["bytes"], id=i + 1, state="uploaded",
                                   browser_download_url="https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.3/" + name)
                              for i, (name, item) in enumerate(expected.items())]
                    release = dict(id=301, tag_name="v5.0.3", draft=False, prerelease=False, assets=assets)
                    (evidence / "release-created.json").write_text(json.dumps(release))
                    api = {
                        "releases/tags/v5.0.3": copy.deepcopy(release),
                        "git/ref/tags/v5.0.3": {"object": {"type": "tag", "sha": "d" * 40}},
                        "git/tags/" + "d" * 40: {"tag": "v5.0.3", "object": {"type": "commit", "sha": SHA}},
                    }
                    if kind == "public_digest":
                        api["releases/tags/v5.0.3"]["assets"][0]["digest"] = "sha256:" + "0" * 64
                    elif kind == "public_duplicate":
                        api["releases/tags/v5.0.3"]["assets"].append(assets[0])
                    elif kind == "tag_source":
                        api["git/tags/" + "d" * 40]["object"]["sha"] = "e" * 40
                    elif kind == "lightweight_tag":
                        api["git/ref/tags/v5.0.3"]["object"]["type"] = "commit"
                    public.api = lambda endpoint: api[endpoint]

                    def fake_download(asset, private, target):
                        data = files[asset["name"]]
                        target.write_bytes(data + b"changed" if kind == "public_bytes" else data)
                        return {"offline_fixture": True}

                    public.download = fake_download
                    work = root / ".build/test.noindex/work"
                    (work / "tmp").mkdir(parents=True)
                    with patch.dict(os.environ, {"TMPDIR": str(work / "tmp")}), \
                            patch.object(sys, "argv", ["public", str(work)]):
                        public.main()
                    accepted = json.loads((work / "provenance.json").read_text())
                    assert accepted["sourceCommit"] == SHA and accepted["version"] == "5.0.3"
                    assert accepted["packageVerified"] and accepted["publicAssetsMatchCandidate"]

        check("proof_accepts_matching_completed_inputs", lambda: provenance_case("proof_only"))
        check("proof_rejects_canonical_change", lambda: provenance_case("canonical_changed"), True)
        check("public_accepts_exact_anonymous_bytes_contract", provenance_case)
        for kind in ("public_digest", "public_duplicate", "tag_source", "lightweight_tag", "public_bytes"):
            check("public_rejects_" + kind, lambda k=kind: provenance_case(k), True)
    return {"all_passed": True, "count": len(PASSED), "passed": PASSED,
            "scope": "Offline fixtures only; no network, credentials, real artifact inspection or app execution.",
            "owned_fixture_scratch_removed": not scratch.exists()}


if __name__ == "__main__":
    with ManagedTemporaryDirectory(prefix="artifact-tools-") as runtime_directory:
        result = main(Path(runtime_directory))
    assert not Path(runtime_directory).exists(), "Runtime owner must finish cleanup before success"
    print(json.dumps(result, indent=2))
