#!/usr/bin/env python3
"""Anonymous public release download; compare every byte to the accepted candidate."""
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
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
SHA = "7f41533b017d26519a69d541d3ffd2dea587f413"
CANDIDATE = ROOT / "dist/github-candidate-v4.3.22-39145124379"
PUBLIC_BASE = "https://github.com/laleoarrow/battery-monitor/releases/download/v4.3.22/"
CURL = ["/usr/bin/curl", "-q", "--http1.1", "--silent", "--show-error", "--fail",
        "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "15"]

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def run(args, timeout):
    try:
        result = subprocess.run(args, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError(Path(args[0]).name + " exceeded its bounded timeout") from None
    require(result.returncode == 0, Path(args[0]).name + " failed (exit " + str(result.returncode) + ")")
    return result.stdout

def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()

def download(asset, private, output):
    name, total, url = asset["name"], asset["size"], asset["browser_download_url"]
    if total < 1024:
        status = run(CURL + ["--location", "--max-time", "60", "--retry", "1", "--retry-delay", "1",
                            "--retry-all-errors", "--output", str(output), "--write-out", "%{http_code}", url], 130)
        require(status == b"200" and output.stat().st_size == total, "Public text response status/length mismatch")
        return {"http_status": 200, "ranges": 0}
    directory = private / name
    directory.mkdir(mode=0o700)
    headers, config = directory / "redirect.headers", directory / "curl.conf"
    run(CURL + ["--max-time", "45", "--retry", "1", "--retry-delay", "1", "--retry-all-errors",
                "--dump-header", str(headers), "--output", "/dev/null", url], 100)
    text = headers.read_text()
    require(re.findall(r"(?m)^HTTP/\S+\s+(\d+)", text)[-1:] == ["302"], "Public asset redirect must be HTTP 302")
    locations = re.findall(r"(?im)^location:\s*(.+)$", text)
    require(len(locations) == 1, "Public asset redirect is missing or ambiguous")
    redirect = locations[0].strip()
    parsed = urlparse(redirect)
    require(parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password
            and not any(character in redirect for character in '\n\r"\\'), "Unsafe public asset redirect")
    # No credentials are used; the signed public CDN redirect is private scratch only.
    config.write_text('url = "' + redirect + '"\n')
    config.chmod(0o600)
    headers.unlink()
    del text, locations, redirect
    chunk = math.ceil(total / 4)
    ranges = [(index, index * chunk, min(total - 1, (index + 1) * chunk - 1)) for index in range(4)]
    def part(item):
        index, begin, end = item
        target, response = directory / ("part-" + str(index)), directory / ("headers-" + str(index))
        run(CURL + ["--max-time", "180", "--speed-limit", "1024", "--speed-time", "30",
            "--retry", "1", "--retry-delay", "1", "--retry-all-errors", "--range", str(begin) + "-" + str(end),
            "--dump-header", str(response), "--output", str(target), "--config", str(config)], 370)
        text = response.read_text()
        require(re.findall(r"(?m)^HTTP/\S+\s+(\d+)", text)[-1:] == ["206"], "Public asset range HTTP status mismatch")
        spans = re.findall(r"(?im)^content-range:\s*bytes (\d+)-(\d+)/(\d+)\s*$", text)
        require(spans and tuple(map(int, spans[-1])) == (begin, end, total), "Public asset range boundary mismatch")
        require(target.stat().st_size == end - begin + 1, "Public asset range length mismatch")
        return target
    with ThreadPoolExecutor(max_workers=4) as pool:
        parts = list(pool.map(part, ranges))
    with output.open("xb") as destination:
        for path in parts:
            with path.open("rb") as source:
                shutil.copyfileobj(source, destination)
    shutil.rmtree(directory)
    return {"http_status": 206, "ranges": len(parts)}

def main():
    os.umask(0o077)
    require(len(sys.argv) == 2, "Expected an owned workspace argument")
    workspace = Path(sys.argv[1]).resolve()
    require(ROOT / ".build" in workspace.parents and any(part.endswith(".noindex") for part in workspace.parts), "Workspace must be project-local .noindex")
    require(Path(os.environ.get("TMPDIR", "")).resolve() == workspace / "tmp", "TMPDIR must be the owned workspace tmp")
    release = json.loads((EVIDENCE / "release-created.json").read_text())
    proof = json.loads((EVIDENCE / "artifact-proof-39145124379.json").read_text())
    require(release["id"] == 416577205 and release["tag_name"] == "v4.3.22" and release["target_commitish"] == SHA
            and not release["draft"] and not release["prerelease"], "Public release identity mismatch")
    require(proof["status"] == "passed" and proof["source_sha"] == SHA and proof["candidate_run_id"] == 39145124379,
            "Accepted candidate proof mismatch")
    expected = proof["exact_four_files"]
    require(len(expected) == 4, "Candidate must contain exactly four installer assets")
    selected = [asset for asset in release["assets"] if asset["name"] in expected]
    require(len(selected) == 4 and len({asset["name"] for asset in selected}) == 4, "Public installer assets are missing or duplicated")
    for asset in selected:
        name = asset["name"]
        require(asset["state"] == "uploaded" and asset["browser_download_url"] == PUBLIC_BASE + name,
                "Unexpected public asset state or URL")
        require(asset["digest"] == "sha256:" + expected[name]["sha256"] and asset["size"] == expected[name]["bytes"],
                "Public API digest/size differs from candidate")
    private, assets = workspace / "private-public-download", workspace / "assets"
    private.mkdir(mode=0o700)
    assets.mkdir()
    started = time.monotonic()
    def fetch(asset):
        target = assets / asset["name"]
        print(asset["name"] + ": anonymous public transfer started", flush=True)
        try:
            transport = download(asset, private, target)
        except RuntimeError as error:
            raise RuntimeError(asset["name"] + ": " + str(error)) from None
        require(target.stat().st_size == asset["size"] and digest(target) == expected[asset["name"]]["sha256"], "Downloaded public file hash/size mismatch")
        run(["/usr/bin/cmp", "-s", str(target), str(CANDIDATE / asset["name"])], 15)
        print(asset["name"] + ": public hash/size and candidate cmp passed", flush=True)
        return asset["name"], {"sha256": digest(target), "bytes": target.stat().st_size,
            "publicURL": asset["browser_download_url"], "releaseAssetID": asset["id"], "cmpToCandidate": True, **transport}
    files = {}
    for group in ([asset for asset in selected if asset["size"] < 1024],
                  [asset for asset in selected if asset["size"] >= 1024]):
        with ThreadPoolExecutor(max_workers=2) as pool:
            files.update(pool.map(fetch, group))
    sums = {}
    for line in (assets / "SHA256SUMS.txt").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        require(match is not None, "Invalid public manifest line")
        checksum, name = match.groups()
        require(name in set(expected) - {"SHA256SUMS.txt"} and name not in sums, "Unexpected or duplicated public manifest entry")
        require(checksum == files[name]["sha256"], "Public manifest checksum mismatch")
        sums[name] = checksum
    require(set(sums) == set(expected) - {"SHA256SUMS.txt"}, "Public manifest must have exactly three entries")
    shutil.rmtree(private)
    result = {"status": "passed", "checkedAtUTC": datetime.now(timezone.utc).isoformat(), "releaseID": release["id"],
        "releaseURL": release["html_url"], "sourceCommit": SHA, "candidateRunID": 39145124379,
        "publicAssetsMatchCandidate": True, "strictThreeEntryManifest": True, "anonymousDownload": True,
        "authentication": "No gh, token, Authorization header, cookies or netrc; curl -q with public URLs and TLS verification",
        "elapsedSeconds": round(time.monotonic() - started, 2), "files": files,
        "inheritedRealVerification": "design/release-v4.3.22/publication/artifact-proof-39145124379.json",
        "inheritedRealVerificationSHA256": digest(EVIDENCE / "artifact-proof-39145124379.json"),
        "rebuildPerformed": False, "structureReverified": False}
    (EVIDENCE / "artifact-public-download-v4.3.22.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print("Four anonymously downloaded public installer assets match candidate hashes and cmp; public manifest passes.", flush=True)

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print("artifact-public-download: " + (str(error) if isinstance(error, RuntimeError) else "Local download or parsing failed"), file=sys.stderr)
        sys.exit(1)
