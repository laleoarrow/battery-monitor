#!/usr/bin/env python3
"""Post-release transport retry; frozen validation main is imported unchanged."""
from datetime import datetime, timezone
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
FROZEN = HERE / "artifact-public-download.py"
MODE, WORKSPACE, RECORD = sys.argv[1], Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve()
SOURCE = os.environ.get("WATTSON_RELEASE_SOURCE_SHA", "")
REDIRECTS = {}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def frozen_hash():
    require(re.fullmatch(r"[0-9a-f]{40}", SOURCE), "Explicit frozen source required")
    content = subprocess.run(["/usr/bin/git", "-C", str(ROOT), "show", SOURCE + ":" + str(FROZEN.relative_to(ROOT))],
                             capture_output=True, check=True, timeout=20).stdout
    expected = hashlib.sha256(content).hexdigest()
    require(sha(FROZEN) == expected, "Public verifier differs from frozen source")
    return expected


def curl(url, target, metadata=False, byte_range=None, redirect_only=False, trusted_cdn=False):
    parsed = urlparse(url)
    allowed_host = parsed.hostname in ("api.github.com", "github.com")
    if trusted_cdn:
        allowed_host = parsed.hostname == "release-assets.githubusercontent.com"
    require(parsed.scheme == "https" and not parsed.username and not parsed.password
            and allowed_host and (trusted_cdn or not parsed.query) and not parsed.fragment
            and not any(character in url for character in "\r\n"), "Unexpected public origin")
    require(not target.exists(), "Transfer output already exists")
    arguments = ["/usr/bin/curl", "-q", "--http1.1", "--max-redirs", "8", "--silent", "--fail",
                 "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "10",
                 "--max-time", "60", "--retry", "2", "--retry-delay", "1", "--retry-all-errors",
                 "--retry-max-time", "150", "--header", "User-Agent: Wattson-public-release-verification",
                 "--output", str(target), "--write-out", "%{http_code}"]
    if not redirect_only:
        arguments.append("--location")
    if metadata:
        arguments += ["--header", "Accept: application/vnd.github+json",
                      "--header", "X-GitHub-Api-Version: 2022-11-28"]
    if redirect_only:
        arguments += ["--header", "Accept: application/octet-stream",
                      "--header", "X-GitHub-Api-Version: 2022-11-28"]
    header_path = target.parent / (target.name + ".headers")
    if byte_range is not None or redirect_only:
        arguments += ["--dump-header", str(header_path)]
    if byte_range is not None:
        arguments += ["--range", str(byte_range[0]) + "-" + str(byte_range[1]),
                      ]
    arguments.append(url)
    try:
        result = subprocess.run(arguments, capture_output=True, timeout=215,
                                env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TMPDIR": str(WORKSPACE / "tmp")})
    except subprocess.TimeoutExpired:
        return {"success": False, "errorClass": "TimeoutExpired", "httpStatus": None}
    status = result.stdout.decode("ascii", "replace").strip()
    status = int(status) if re.fullmatch(r"[0-9]{3}", status) else None
    expected_status = 302 if redirect_only else 206 if byte_range is not None else 200
    report = {"success": result.returncode == 0 and status == expected_status,
            "errorClass": None if result.returncode == 0 else "CurlExit" + str(result.returncode),
            "curlExitCode": result.returncode, "httpStatus": status}
    if byte_range is not None:
        spans = re.findall(rb"(?im)^content-range:\s*bytes (\d+)-(\d+)/(\d+)\s*$", header_path.read_bytes()) if header_path.is_file() else []
        span = tuple(map(int, spans[-1])) if spans else None
        exact = span == byte_range and target.is_file() and target.stat().st_size == byte_range[1] - byte_range[0] + 1
        report.update(contentRange=list(span) if span else None, exactContentRangeAndLength=exact)
        report["success"] = report["success"] and exact
        header_path.unlink(missing_ok=True)
    return report


def resolve_redirect(asset, private):
    expected = "https://api.github.com/repos/laleoarrow/battery-monitor/releases/assets/" + str(asset["id"])
    require(asset["url"] == expected, "Unexpected anonymous REST asset origin")
    target = private / (asset["name"] + ".redirect-body")
    result = curl(expected, target, redirect_only=True)
    require(result["success"], "Anonymous REST asset redirect failed: " + str(result.get("errorClass")))
    headers = target.parent / (target.name + ".headers")
    locations = re.findall(rb"(?im)^location:\s*([^\r\n]+)", headers.read_bytes())
    require(len(locations) == 1, "Anonymous REST redirect Location missing or ambiguous")
    location = locations[0].decode("ascii").strip()
    parsed = urlparse(location)
    require(parsed.scheme == "https" and parsed.hostname == "release-assets.githubusercontent.com"
            and not parsed.username and not parsed.password and not any(c in location for c in "\r\n"),
            "Untrusted anonymous CDN redirect")
    headers.unlink(); target.unlink(missing_ok=True)
    REDIRECTS[asset["id"]] = location
    return location


def asset_transfer(asset, target):
    result = curl(asset["browser_download_url"], target)
    exact = result["success"] and target.is_file() and not target.is_symlink() \
        and target.stat().st_size == asset["size"] and "sha256:" + sha(target) == asset["digest"]
    return {**result, "exactSizeAndAPIDigestMatch": bool(exact),
            "bytes": target.stat().st_size if target.is_file() else None,
            "sha256": sha(target) if target.is_file() else None}


def range_transfer(asset, private, output):
    total, chunk = asset["size"], 128 * 1024
    directory = private / asset["name"]
    directory.mkdir(mode=0o700)
    intervals = [(index, begin, min(begin + chunk, total) - 1)
                 for index, begin in enumerate(range(0, total, chunk))]

    def part(interval):
        index, begin, end = interval
        path = directory / str(index)
        result = curl(REDIRECTS[asset["id"]], path, byte_range=(begin, end, total), trusted_cdn=True)
        require(result["success"], "Curl range failed HTTP206/content-range/length: " + asset["name"] + " chunk " + str(index) + " " + str(result.get("errorClass")))
        return path, {"begin": begin, "end": end, "httpStatus": 206, "sha256": sha(path)}

    with ThreadPoolExecutor(max_workers=8) as pool:
        parts = list(pool.map(part, intervals))
    with output.open("xb") as destination:
        for path, _ in parts:
            with path.open("rb") as source:
                shutil.copyfileobj(source, destination)
    require(output.stat().st_size == total and "sha256:" + sha(output) == asset["digest"],
            "Assembled curl ranges differ from API size/digest")
    shutil.rmtree(directory)
    print("Verified " + str(len(parts)) + " curl ranges: " + asset["name"], flush=True)
    return {"http_status": 206, "ranges": len(parts), "rangeBytes": chunk, "maxWorkers": 8,
            "everyRangeContentRangeAndLengthVerified": True, "rangeChecks": [item for _, item in parts]}


def main():
    require(MODE in ("diagnose", "verify") and WORKSPACE.is_dir() and ROOT / ".build" in WORKSPACE.parents
            and any(p.endswith(".noindex") for p in WORKSPACE.parts), "Invalid owned retry workspace")
    require(RECORD.is_dir() and RECORD.parent == HERE
            and RECORD.name.startswith("artifact-public-curl-retry-review."), "Invalid retry evidence")
    frozen = frozen_hash()
    specification = importlib.util.spec_from_file_location("frozen_public_verifier", FROZEN)
    original = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(original)
    if MODE == "diagnose":
        private = WORKSPACE / "diagnostics"
        private.mkdir(mode=0o700)
        metadata = curl("https://api.github.com/repos/laleoarrow/battery-monitor/releases/tags/v5.0.1",
                        private / "release.json", metadata=True)
        evidence = {"checkedAtUTC": datetime.now(timezone.utc).isoformat(), "frozenModuleSHA256": frozen,
                    "metadata": metadata, "assets": {}, "scope": "Anonymous transport only; no release acceptance."}
        if metadata["success"]:
            try:
                release = json.loads((private / "release.json").read_text())
                assets = [a for a in release["assets"] if a["name"] in original.NAMES]
                require(len(assets) == 4 and {a["name"] for a in assets} == original.NAMES,
                        "Diagnostic four-file API set mismatch")
                for asset in assets:
                    require(asset["browser_download_url"] ==
                            "https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.1/" + asset["name"],
                            "Diagnostic public URL mismatch")
                with ThreadPoolExecutor(max_workers=4) as pool:
                    results = list(pool.map(lambda a: asset_transfer(a, private / a["name"]), assets))
                evidence["assets"] = {a["name"]: r for a, r in zip(assets, results)}
            except Exception as error:
                evidence["metadataParseErrorClass"] = type(error).__name__
        evidence["allFourNormalDownloadsReliable"] = len(evidence["assets"]) == 4 and all(
            r["exactSizeAndAPIDigestMatch"] for r in evidence["assets"].values())
        with (RECORD / "transport-diagnostics.json").open("x") as output:
            json.dump(evidence, output, indent=2, sort_keys=True); output.write("\n")
        require(evidence["allFourNormalDownloadsReliable"], "Normal public curl transport did not pass all four assets")
        print("Anonymous API and four normal public downloads passed transport size/digest checks.")
        return

    probe_private = WORKSPACE / "first-range-probes"
    probe_private.mkdir(mode=0o700)
    metadata_result = curl("https://api.github.com/repos/laleoarrow/battery-monitor/releases/tags/v5.0.1",
                           probe_private / "release.json", metadata=True)
    require(metadata_result["success"], "Anonymous metadata probe failed")
    release = json.loads((probe_private / "release.json").read_text())
    large_assets = [asset for asset in release["assets"] if asset["name"] in original.NAMES and asset["size"] >= 1024]
    require(len(large_assets) == 2, "First-range probe expected both large assets")
    probes = {}
    for asset in large_assets:
        require(asset["browser_download_url"] == "https://github.com/laleoarrow/battery-monitor/releases/download/v5.0.1/" + asset["name"], "First-range public URL mismatch")
        redirect = resolve_redirect(asset, probe_private)
        probes[asset["name"]] = curl(redirect, probe_private / asset["name"], byte_range=(0, 128 * 1024 - 1, asset["size"]), trusted_cdn=True)
    probe_record = {"checkedAtUTC": datetime.now(timezone.utc).isoformat(), "metadata": metadata_result,
                    "firstRangeProbes": probes, "allPassed": all(result["success"] for result in probes.values())}
    with (RECORD / "first-range-probes.json").open("x") as destination:
        json.dump(probe_record, destination, indent=2, sort_keys=True); destination.write("\n")
    require(probe_record["allPassed"], "One or both large first-range probes failed")
    print("First 128 KiB HTTP206 probes passed for both large assets.", flush=True)

    def download(asset, private, output):
        require(asset["url"] == "https://api.github.com/repos/laleoarrow/battery-monitor/releases/assets/" + str(asset["id"]), "Unexpected anonymous REST asset origin")
        if asset["size"] >= 1024:
            if asset["id"] not in REDIRECTS:
                resolve_redirect(asset, private)
            result = range_transfer(asset, private, output)
        else:
            redirect = resolve_redirect(asset, private)
            transfer = curl(redirect, output, trusted_cdn=True)
            require(transfer["success"] and output.stat().st_size == asset["size"] and "sha256:" + sha(output) == asset["digest"], "Curl public text download failed exact size/digest validation")
            result = {"http_status": 200, "ranges": 0}
        return {**result, "transportMethod": "curl HTTP/1.1 HTTPS validated anonymous REST/CDN redirect; bounded ranges for large assets",
                "anonymousBrowserDownloadURL": asset["browser_download_url"],
                "anonymousRESTAssetURL": asset["url"], "CDNRedirectQueryNotLogged": True,
                "connectTimeoutSeconds": 10, "requestTimeoutSeconds": 60, "retries": 2,
                "curlConfigDisabled": True, "curlEnvironmentAllowlist": ["PATH", "LC_ALL", "TMPDIR"],
                "authorizationCookiesAndNetrcAbsent": True}

    original.download = download
    sys.argv = [str(FROZEN), str(WORKSPACE)]
    original.main()
    require(frozen_hash() == frozen, "Frozen verifier changed during public verification")
    provenance_path = WORKSPACE / "provenance.json"
    original_provenance_sha = sha(provenance_path)
    provenance = json.loads(provenance_path.read_text())
    before_validation = {key: value for key, value in provenance.items() if key != "authentication"}
    provenance["authentication"] = "Anonymous urllib REST metadata and bounded curl HTTP/1.1 HTTPS anonymous REST/CDN redirect ranges/text; no gh, token, Authorization header, cookies, netrc or inherited auth environment; default TLS verification"
    require({key: value for key, value in provenance.items() if key != "authentication"} == before_validation,
            "Validation fields changed")
    provenance_path.write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n")
    binding = {"checkedAtUTC": datetime.now(timezone.utc).isoformat(), "sourceCommit": SOURCE,
               "frozenModuleSHA256": frozen, "frozenModuleMatchesSourceCommit": True,
               "onlyImportedFunctionReplaced": "download", "unchangedMainCompleted": True,
               "originalStagedProvenanceSHA256": original_provenance_sha,
               "truthfulFinalProvenanceSHA256": sha(provenance_path),
               "onlyProvenanceDescriptionCorrected": "authentication", "validationFieldsUnchanged": True,
               "transport": "Bounded anonymous curl HTTP/1.1; validated anonymous REST asset IDs to private HTTPS release-assets.githubusercontent.com redirects; 128 KiB ranges, <=8 workers, exact HTTP206/Content-Range/length per chunk; HTTP200 text; assembled exact API size/digest; every unchanged main guard."}
    with (RECORD / "transport-binding.json").open("x") as output:
        json.dump(binding, output, indent=2, sort_keys=True); output.write("\n")
    print("Unchanged frozen validation main passed with explicitly recorded curl transport.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("artifact-public-curl-retry: " + (str(error) if isinstance(error, RuntimeError)
              else type(error).__name__), file=sys.stderr)
        sys.exit(1)
