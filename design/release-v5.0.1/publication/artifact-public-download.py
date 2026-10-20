#!/usr/bin/env python3
"""Anonymous exact public-byte verification; reuse accepted candidate inspection."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse
import hashlib
import json
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
SHA = None
RUN = None
REPO_API = "https://api.github.com/repos/laleoarrow/battery-monitor/"
CANDIDATE = None
NAMES = {"SHA256SUMS.txt", "Wattson-v5.0.1-macos-universal.pkg",
         "Wattson-v5.0.1-macos-universal.dmg", "Wattson-v5.0.1-release-info.txt"}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def api(endpoint):
    request = urllib.request.Request(REPO_API + endpoint, headers={
        "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "Wattson-public-release-verification"})
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=15) as reply:
        require(reply.status == 200, "Anonymous GitHub metadata status mismatch")
        payload = reply.read(2_000_001)
        require(len(payload) <= 2_000_000, "Anonymous GitHub metadata exceeds limit")
        return json.loads(payload)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def read_bounded(response, count):
    deadline, payload = time.monotonic() + 25, bytearray()
    while len(payload) <= count:
        require(time.monotonic() <= deadline, "Anonymous response exceeded elapsed bound")
        data = response.read1(min(16384, count + 1 - len(payload)))
        if not data:
            break
        payload.extend(data)
    require(len(payload) == count, "Anonymous response length mismatch")
    return bytes(payload)

def download(asset, private, output):
    api = "https://api.github.com/repos/laleoarrow/battery-monitor/releases/assets/" + str(asset["id"])
    require(asset["url"] == api, "Unexpected anonymous REST asset origin")
    headers = {"Accept": "application/octet-stream", "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "Wattson-public-release-verification"}
    response, redirect = None, None
    try:
        response = urllib.request.build_opener(NoRedirect()).open(urllib.request.Request(api, headers=headers), timeout=15)
    except urllib.error.HTTPError as error:
        require(error.code == 302, "Anonymous public API HTTP " + str(error.code))
        redirect = error.headers.get("Location", "")
        parsed = urlparse(redirect)
        require(parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password
                         and not any(c in redirect for c in "\r\n"), "Unsafe anonymous public CDN redirect")
        error.close()
    if asset["size"] < 1024:
        if response is None:
            response = urllib.request.build_opener(NoRedirect()).open(urllib.request.Request(redirect), timeout=10)
        with response:
            require(response.status == 200, "Anonymous public text status mismatch")
            output.write_bytes(read_bounded(response, asset["size"]))
        return {"http_status": 200, "ranges": 0, "anonymousRESTAssetURL": api}
    if response is not None:
        response.close()
        raise RuntimeError("Anonymous public large asset must redirect")
    directory = private / asset["name"]
    directory.mkdir(mode=0o700)
    total, chunk = asset["size"], 262144
    count = (total + chunk - 1) // chunk
    def get_range(begin, end):
        request = urllib.request.Request(redirect, headers={"Range": "bytes=" + str(begin) + "-" + str(end)})
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=10) as reply:
            require(reply.status == 206 and reply.headers.get("Content-Range") == "bytes " + str(begin) + "-" + str(end) + "/" + str(total), "Anonymous public CDN range boundary mismatch")
            return read_bounded(reply, end - begin + 1)
    def part(index):
        begin, end = index * chunk, min(total, (index + 1) * chunk) - 1
        split = False
        try:
            payload = get_range(begin, end)
        except Exception:
            middle = (begin + end + 1) // 2
            try:
                payload = get_range(begin, middle - 1) + get_range(middle, end)
                split = True
            except Exception as error:
                raise RuntimeError("Anonymous public CDN split retry failed (" + type(error).__name__ + ")") from None
        require(len(payload) == end - begin + 1, "Anonymous public assembled range length mismatch")
        target = directory / str(index)
        target.write_bytes(payload)
        return target, split
    with ThreadPoolExecutor(max_workers=8) as pool:
        parts = list(pool.map(part, range(count)))
    with output.open("xb") as destination:
        for path, _ in parts:
            destination.write(path.read_bytes())
    shutil.rmtree(directory)
    return {"http_status": 206, "ranges": count, "rangeBytes": chunk,
            "boundedSplitRetries": sum(split for _, split in parts), "anonymousRESTAssetURL": api}


def main():
    global SHA, RUN, CANDIDATE
    SHA = os.environ.get("WATTSON_RELEASE_SOURCE_SHA", "")
    run = os.environ.get("WATTSON_RELEASE_CANDIDATE_RUN_ID", "")
    require(re.fullmatch(r"[0-9a-f]{40}", SHA) is not None
            and re.fullmatch(r"[1-9][0-9]+", run) is not None,
            "Expected explicit frozen source SHA and candidate run ID")
    RUN = int(run)
    CANDIDATE = ROOT / "dist" / f"github-candidate-v5.0.1-{RUN}"
    os.umask(0o077)
    require(len(sys.argv) == 2, "Expected owned workspace")
    workspace = Path(sys.argv[1]).resolve()
    require(workspace.is_dir() and ROOT / ".build" in workspace.parents
            and any(x.endswith(".noindex") for x in workspace.parts), "Invalid owned workspace")
    require(Path(os.environ.get("TMPDIR", "")).resolve() == workspace / "tmp", "Invalid owned TMPDIR")
    proofs = list(EVIDENCE.glob(f"artifact-{RUN}-review.*/artifact-proof.json"))
    require(len(proofs) == 1, "Expected exactly one accepted candidate proof")
    proof = json.loads(proofs[0].read_text())
    require(proof["candidate_checks_passed"] is True and proof["run_id"] == RUN
            and proof["source_sha"] == SHA and proof["version"] == "5.0.1", "Candidate proof identity mismatch")
    for name, sha in proof["evidence_sha256"].items():
        require(digest(proofs[0].parent / name) == sha, "Candidate evidence was changed")
    require(not Path((proofs[0].parent / "artifact-workspace.txt").read_text().strip()).exists(),
            "Candidate inspection cleanup has not completed")
    expected = json.loads((proofs[0].parent / "artifact-download.json").read_text())["files"]
    require(set(expected) == NAMES and CANDIDATE.is_dir() and not CANDIDATE.is_symlink()
            and {p.name for p in CANDIDATE.iterdir()} == NAMES, "Candidate four-file set mismatch")
    for name, item in expected.items():
        path = CANDIDATE / name
        require(path.is_file() and not path.is_symlink() and path.stat().st_size == item["bytes"]
                and digest(path) == item["sha256"], "Accepted candidate bytes changed")
    saved = json.loads((EVIDENCE / "release-created.json").read_text())
    release = api("releases/tags/v5.0.1")
    require(saved["id"] == release["id"], "Public release ID differs from publication record")
    for metadata in (saved, release):
        require(metadata["tag_name"] == "v5.0.1" and metadata["draft"] is False
                and metadata["prerelease"] is False, "Public stable release identity mismatch")
    ref = api("git/ref/tags/v5.0.1")
    require(ref["object"]["type"] == "tag" and re.fullmatch(r"[0-9a-f]{40}", ref["object"]["sha"]),
            "Public release must use an annotated tag")
    tag = api("git/tags/" + ref["object"]["sha"])
    require(tag["tag"] == "v5.0.1" and tag["object"]["type"] == "commit"
            and tag["object"]["sha"] == SHA, "Annotated public tag source mismatch")
    selected = []
    for name, item in expected.items():
        for metadata in (saved, release):
            matches = [a for a in metadata["assets"] if a["name"] == name]
            require(len(matches) == 1 and matches[0]["digest"] == "sha256:" + item["sha256"]
                    and matches[0]["size"] == item["bytes"], "Public API asset digest/size mismatch")
        asset = matches[0]
        require(asset["state"] == "uploaded" and asset["browser_download_url"] ==
                "https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.1/" + name,
                "Unexpected public asset state/URL")
        selected.append(asset)
    private, assets = workspace / "private-public-download", workspace / "assets"
    private.mkdir(mode=0o700); assets.mkdir()
    files = {}
    for asset in selected:
        target = assets / asset["name"]
        transport = download(asset, private, target)
        require(target.stat().st_size == expected[asset["name"]]["bytes"]
                and digest(target) == expected[asset["name"]]["sha256"]
                and target.read_bytes() == (CANDIDATE / asset["name"]).read_bytes(),
                "Anonymous public bytes differ from accepted candidate")
        files[asset["name"]] = {"sha256": digest(target), "bytes": target.stat().st_size,
            "publicURL": asset["browser_download_url"], "releaseAssetID": asset["id"],
            "cmpToCandidate": True, **transport}
    sums = {}
    for line in (assets / "SHA256SUMS.txt").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        require(match is not None and match[2] in NAMES - {"SHA256SUMS.txt"}
                and match[2] not in sums, "Invalid or duplicate public manifest entry")
        require(match[1] == files[match[2]]["sha256"], "Public manifest checksum mismatch")
        sums[match[2]] = match[1]
    require(set(sums) == NAMES - {"SHA256SUMS.txt"}, "Public manifest must cover exactly three files")
    result = {"checkedAtUTC": datetime.now(timezone.utc).isoformat(), "version": "5.0.1",
        "sourceCommit": SHA, "candidateRunID": RUN, "releaseID": release["id"],
        "packageSHA256": files["Wattson-v5.0.1-macos-universal.pkg"]["sha256"],
        "publicAssetsMatchCandidate": True, "packageVerified": True,
        "publicAssetDirectory": str(ROOT / "dist/public-v5.0.1-verify"),
        "candidateProof": str(proofs[0]), "candidateProofSHA256": digest(proofs[0]),
        "anonymousDownload": True, "strictThreeEntryManifest": True, "files": files,
        "authentication": "Anonymous urllib REST/CDN, no gh, token, Authorization header, cookies or netrc; default TLS verification",
        "structureReverified": False, "rebuildPerformed": False,
        "verificationInheritance": "Exact public byte equality inherits the accepted candidate frozen verifier and per-slice signature/entitlement inspection."}
    (workspace / "provenance.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print("Four anonymous public assets match accepted candidate; provenance staged.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("artifact-public-download: " + (str(error) if isinstance(error, RuntimeError)
              else "Anonymous transfer or parsing failed"), file=sys.stderr)
        sys.exit(1)
