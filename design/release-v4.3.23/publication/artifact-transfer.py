#!/usr/bin/env python3
"""Bounded, credential-private transfer of one immutable candidate artifact."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse
import hashlib
import json
import math
import os
import re
import shutil
import stat
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
RUN = None
HEADLESS_RUN = 39218951312
SHA = "23185f299ce61b8e373ebf5115b461ad2aa01226"
REPO = "laleoarrow/battery-monitor"
NAME = "Wattson-release-candidate-v4.3.23"
EXPECTED_JOBS = {"Build universal PKG and DMG once", "Install on macos-14", "Install on macos-15",
                 "Install on macos-26", "Install on macos-15-intel", "Install on macos-26-intel"}
BUILD = "Build universal PKG and DMG once"
FILES = {"SHA256SUMS.txt", "Wattson-v4.3.23-macos-universal.pkg",
         "Wattson-v4.3.23-macos-universal.dmg", "Wattson-v4.3.23-release-info.txt"}
METADATA = dict(version="4.3.23", build_number="4.3.23", architectures="arm64,x86_64",
    minimum_macos="12.0", install_path="/Applications/Wattson.app",
    helper_path="/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper",
    dmg_contents="app-only", pkg_contents="app-and-helper", distribution_mode="community-ad-hoc",
    app_signature="ad-hoc", helper_signature="ad-hoc", package_signature="unsigned",
    dmg_signature="unsigned", notarized="no", stapled="no")

class QueryUnavailable(Exception):
    pass

def require(value, message):
    if not value:
        raise RuntimeError(message)

def save(name, value):
    path = EVIDENCE / ("artifact-" + name + ".json")
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")

def run(args, timeout=45, data=None):
    try:
        result = subprocess.run(args, input=data, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError(Path(args[0]).name + " exceeded its bounded timeout") from None
    require(result.returncode == 0, Path(args[0]).name + " failed (exit " + str(result.returncode) + ")")
    return result.stdout

def api(endpoint):
    try:
        result = run(["/opt/homebrew/bin/gh", "api", "repos/" + REPO + "/" + endpoint])
    except RuntimeError:
        raise QueryUnavailable() from None
    return json.loads(result)

def ready(workspace):
    workflow = api("actions/runs/" + str(RUN))
    keys = ("id", "head_sha", "head_branch", "path", "event", "status", "conclusion", "run_attempt", "html_url")
    save("run", {key: workflow.get(key) for key in keys})
    require((workflow["id"], workflow["head_sha"], workflow["head_branch"], workflow["path"], workflow["event"], workflow["run_attempt"])
            == (RUN, SHA, "main", ".github/workflows/macos-helper-install.yml", "workflow_dispatch", 1), "Candidate identity mismatch")
    if workflow["status"] != "completed":
        print("Candidate is not complete; no download or wait. Invoke again after success.", flush=True)
        return 3
    require(workflow["conclusion"] == "success", "Candidate failed; download prohibited")
    require(api("git/ref/heads/main")["object"]["sha"] == SHA, "Remote main is no longer frozen")
    headless = api("actions/runs/" + str(HEADLESS_RUN))
    save("headless", {key: headless.get(key) for key in keys})
    require((headless["id"], headless["head_sha"], headless["head_branch"], headless["path"],
             headless["event"], headless["status"], headless["conclusion"])
            == (HEADLESS_RUN, SHA, "main", ".github/workflows/ci.yml", "push", "completed", "success"),
            "Frozen main Headless CI is not successful")
    listing = api("actions/runs/" + str(RUN) + "/jobs?per_page=100")
    jobs = listing["jobs"]
    save("jobs", [{key: job.get(key) for key in ("id", "name", "status", "conclusion", "started_at", "completed_at")} for job in jobs])
    require(listing["total_count"] == len(jobs) == 6 and {job["name"] for job in jobs} == EXPECTED_JOBS,
            "Candidate must contain exactly the build and five install jobs")
    require(all(job["status"] == "completed" and job["conclusion"] == "success" for job in jobs),
            "Every candidate build/install job must pass")
    listing = api("actions/runs/" + str(RUN) + "/artifacts?per_page=100")
    require(listing["total_count"] == len(listing["artifacts"]), "Artifact listing was truncated")
    artifacts = listing["artifacts"]
    save("list", {"total_count": listing["total_count"], "artifacts": artifacts})
    matches = [artifact for artifact in artifacts if artifact["name"] == NAME]
    require(len(matches) == 1, "Expected exactly one matching candidate artifact")
    artifact = matches[0]
    require(not artifact["expired"], "Candidate artifact expired")
    binding = artifact["workflow_run"]
    require((binding["id"], binding["head_sha"], binding["head_branch"]) == (RUN, SHA, "main"), "Artifact source binding mismatch")
    require(re.fullmatch(r"sha256:[0-9a-f]{64}", artifact["digest"]) is not None and artifact["size_in_bytes"] > 0, "Missing artifact digest or size")
    (workspace / "artifact.json").write_text(json.dumps(artifact))
    save("metadata", artifact)
    print("All candidate jobs passed; artifact " + str(artifact["id"]) + " is ready.", flush=True)
    return 0


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()

def safe_url(value):
    parsed = urlparse(value)
    require(parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password
            and not any(character in value for character in '\n\r"\\'), "Unsafe redirect URL")
    return value

def download(workspace):
    started = time.monotonic()
    artifact = json.loads((workspace / "artifact.json").read_text())
    private = workspace / "private-transfer"
    private.mkdir(mode=0o700)
    config = private / "curl.conf"
    headers = private / "redirect.headers"
    # Token/config and signed headers remain only in this registered private workspace.
    token = run(["/opt/homebrew/bin/gh", "auth", "token"]).decode().strip()
    require(token and not any(character in token for character in '\n\r"\\'), "Invalid authentication token")
    api_url = "https://api.github.com/repos/" + REPO + "/actions/artifacts/" + str(artifact["id"]) + "/zip"
    config.write_text('url = "' + api_url + '"\nheader = "Accept: application/vnd.github+json"\nheader = "Authorization: Bearer ' + token + '"\n')
    config.chmod(0o600)
    del token
    common = ["/usr/bin/curl", "-q", "--http1.1", "--silent", "--show-error", "--fail",
              "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "15"]
    run(common + ["--max-time", "45", "--dump-header", str(headers), "--output", "/dev/null", "--config", str(config)], 50)
    header_text = headers.read_text()
    require(re.findall(r"(?m)^HTTP/\S+\s+(\d+)", header_text)[-1:] == ["302"], "Artifact redirect was not HTTP 302")
    locations = re.findall(r"(?im)^location:\s*(.+)$", header_text)
    require(len(locations) == 1, "Artifact redirect Location missing or ambiguous")
    config.write_text('url = "' + safe_url(locations[0].strip()) + '"\n')
    headers.unlink()
    del header_text, locations
    total = artifact["size_in_bytes"]
    count = min(8, total)
    chunk = math.ceil(total / count)
    ranges = [(i, i * chunk, min(total - 1, (i + 1) * chunk - 1)) for i in range(count) if i * chunk < total]
    def part(item):
        index, begin, end = item
        target, response = private / ("part-" + str(index)), private / ("headers-" + str(index))
        run(common + ["--max-time", "180", "--speed-limit", "1024", "--speed-time", "30",
            "--retry", "1", "--retry-delay", "1", "--retry-all-errors", "--range", str(begin) + "-" + str(end),
            "--dump-header", str(response), "--output", str(target), "--config", str(config)], 370)
        text = response.read_text()
        require(re.findall(r"(?m)^HTTP/\S+\s+(\d+)", text)[-1:] == ["206"], "Artifact range HTTP status mismatch")
        spans = re.findall(r"(?im)^content-range:\s*bytes (\d+)-(\d+)/(\d+)\s*$", text)
        require(spans and tuple(map(int, spans[-1])) == (begin, end, total), "Artifact range boundary mismatch")
        require(target.stat().st_size == end - begin + 1, "Artifact range length mismatch")
        return target
    with ThreadPoolExecutor(max_workers=8) as pool:
        parts = list(pool.map(part, ranges))
    archive = workspace / "artifact.zip"
    with archive.open("xb") as destination:
        for path in parts:
            with path.open("rb") as source:
                shutil.copyfileobj(source, destination)
    archive_hash = digest(archive)
    require(archive.stat().st_size == total and "sha256:" + archive_hash == artifact["digest"], "Artifact archive digest/size mismatch")
    assets = workspace / "assets"
    assets.mkdir()
    with zipfile.ZipFile(archive) as zipped:
        entries = zipped.infolist()
        require(len(entries) == 4 and set(zipped.namelist()) == FILES, "Artifact ZIP must contain exactly four expected files")
        for entry in entries:
            require(not entry.is_dir() and not entry.flag_bits & 1
                    and stat.S_IFMT(entry.external_attr >> 16) in (0, stat.S_IFREG)
                    and entry.filename == Path(entry.filename).name and "\\" not in entry.filename,
                    "Unsafe artifact ZIP entry")
        require(zipped.testzip() is None, "Artifact ZIP CRC mismatch")
        for entry in entries:
            with zipped.open(entry) as source, (assets / entry.filename).open("xb") as destination:
                shutil.copyfileobj(source, destination)
    checksums = {}
    for line in (assets / "SHA256SUMS.txt").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        require(match is not None, "Invalid manifest line")
        checksum, name = match.groups()
        require(name in FILES - {"SHA256SUMS.txt"} and name not in checksums, "Manifest name duplicated or unexpected")
        require(digest(assets / name) == checksum, "Manifest checksum mismatch")
        checksums[name] = checksum
    require(set(checksums) == FILES - {"SHA256SUMS.txt"}, "Manifest must cover exactly three release files")
    metadata = {}
    for line in (assets / "Wattson-v4.3.23-release-info.txt").read_text().splitlines():
        require("=" in line, "Malformed release metadata")
        key, value = line.split("=", 1)
        require(key not in metadata, "Duplicate release metadata key")
        metadata[key] = value
    require(metadata == METADATA, "Release metadata differs from exact community contract")
    save("download", {"checked_at_utc": datetime.now(timezone.utc).isoformat(), "run_id": RUN,
        "source_sha": SHA, "artifact_id": artifact["id"], "archive_sha256": archive_hash,
        "archive_bytes": total, "github_digest_and_size_match": True, "verified_http206_ranges": len(parts),
        "zip_exact_four_and_crc_valid": True, "strict_manifest_valid": True, "strict_metadata_valid": True,
        "metadata": metadata, "files": {name: {"sha256": digest(assets / name), "bytes": (assets / name).stat().st_size} for name in sorted(FILES)},
        "elapsed_seconds": round(time.monotonic() - started, 2), "transport": "TLS-verified HTTP/1.1; authorization only to GitHub API; signed redirect only in private scratch; no raw curl output retained"})
    shutil.rmtree(private)
    print("Exact four candidate assets downloaded; archive digest, manifest and metadata pass.", flush=True)

def main():
    global RUN, EVIDENCE
    os.umask(0o077)
    require(len(sys.argv) == 5 and sys.argv[1] in ("ready", "download")
            and re.fullmatch(r"[1-9][0-9]+", sys.argv[2]) is not None,
            "Usage: ready|download RUN-ID OWNED-WORKSPACE EVIDENCE-DIRECTORY")
    RUN = int(sys.argv[2])
    workspace = Path(sys.argv[3]).resolve()
    require(workspace.is_dir() and ROOT / ".build" in workspace.parents
            and any(part.endswith(".noindex") for part in workspace.parts),
            "Transfer workspace must be project-local .noindex")
    EVIDENCE = Path(sys.argv[4]).resolve()
    require(EVIDENCE.is_dir() and EVIDENCE.parent == Path(__file__).resolve().parent
            and EVIDENCE.name.startswith("artifact-" + str(RUN) + "-review."),
            "Evidence directory must be this run's owned publication record")
    if sys.argv[1] == "ready":
        return ready(workspace)
    download(workspace)
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except QueryUnavailable:
        print("artifact-transfer: read-only GitHub query unavailable; no download.", file=sys.stderr)
        sys.exit(4)
    except (RuntimeError, OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        # Exception messages from external tools/URLs are intentionally not printed.
        message = str(error) if isinstance(error, RuntimeError) else "Local artifact transfer or parsing failed"
        print("artifact-transfer: " + message, file=sys.stderr)
        sys.exit(1)
