#!/usr/bin/env python3
"""Read-only, credential-free Pages verification for the frozen 5.0.2 release.

Run --source-only before Pages is ready. Public acceptance requires the parent
coordinator's explicit Pages-success flag and exact workflow SHA. Downloads and
ZIP checks stay in memory; only the explicitly requested final JSON is written.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[3]
FROZEN_SHA = None
VERSION = "5.0.2"
SOURCE = f"design/releases/v{VERSION}/"
SITE = "https://laleoarrow.github.io/battery-monitor/"
GALLERY = f"{SITE}design/v{VERSION}/"
LATEST_API = "https://api.github.com/repos/laleoarrow/battery-monitor/releases/latest"
SVG_FAMILIES = {"modules": 6, "sidebar": 3, "general": 5, "power": 6}
PREVIEW_PATHS = {
    "previews/vector-preview.png", "previews/sidebar-vector-preview.png",
    "previews/general-vector-preview.png", "previews/power-vector-preview.png",
    "previews/power-state-matrix.png", "previews/time-source-light.png",
    "previews/time-source-dark.png",
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def frozen_bytes(path):
    return subprocess.check_output(
        ["git", "show", f"{FROZEN_SHA}:{path}"], cwd=ROOT
    )


def validate_zip_masters(files, manifest):
    require({item["path"] for item in manifest["sourcePackages"]} == {
        f"Wattson-v{VERSION}-{family.title()}-SVG.zip" for family in SVG_FAMILIES
    } and len(manifest["sourcePackages"]) == 4, "Expected exactly the four versioned SVG packages")
    require(len(manifest["svgSources"]) == sum(SVG_FAMILIES.values()), "Expected 20 SVG masters")
    total = 0
    results = []
    for package in manifest["sourcePackages"]:
        name = package["path"]
        data = files[name]
        require(digest(data) == package["sha256"], f"Package hash: {name}")
        family = name.split("-")[-2].lower()
        expected = {
            PurePosixPath(item["copy"]).name: frozen_bytes(item["source"])
            for item in manifest["svgSources"]
            if PurePosixPath(item["copy"]).parent == PurePosixPath(f"svg/{family}")
        }
        require(len(expected) == SVG_FAMILIES[family], f"SVG family count: {family}")
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            require(archive.testzip() is None, f"ZIP CRC: {name}")
            members = archive.namelist()
            prefix = name.removesuffix(".zip") + "/"
            require(all(member.startswith(prefix) and ".." not in PurePosixPath(member).parts
                        for member in members), f"ZIP member path: {name}")
            svg_members = [member for member in members if member.endswith(".svg")]
            require({PurePosixPath(member).name for member in svg_members} == set(expected),
                    f"ZIP SVG set: {name}")
            require(len(svg_members) == package["runtimeMasterCount"], f"SVG count: {name}")
            for member in svg_members:
                require(archive.read(member) == expected[PurePosixPath(member).name],
                        f"Frozen master mismatch: {name}/{member}")
        total += len(expected)
        results.append({"path": name, "crcOK": True, "exactFrozenMasters": len(expected),
                        "sha256": digest(data), "bytes": len(data)})
    require(total == 20 and len(results) == 4, "Expected four ZIPs with 20 frozen SVG masters")
    return results


def load_frozen():
    require(frozen_bytes("VERSION").decode().strip() == VERSION, "Frozen VERSION mismatch")
    checksum_bytes = frozen_bytes(SOURCE + "SHA256SUMS.txt")
    expected = {}
    for line in checksum_bytes.decode().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        require(match is not None, "Invalid frozen checksum manifest")
        name = match[2]
        path = PurePosixPath(name)
        require(not path.is_absolute() and ".." not in path.parts and name not in expected,
                f"Unsafe or duplicate checksum path: {name}")
        expected[name] = match[1]
    tree = subprocess.check_output(
        ["git", "ls-tree", "-r", "--name-only", FROZEN_SHA, "--", SOURCE], cwd=ROOT
    ).decode().splitlines()
    gallery_files = {path.removeprefix(SOURCE) for path in tree}
    require("SHA256SUMS.txt" in gallery_files and set(expected) == gallery_files - {"SHA256SUMS.txt"},
            "Checksums must cover every frozen gallery file exactly once")
    files = {name: frozen_bytes(SOURCE + name) for name in expected}
    for name, data in files.items():
        require(digest(data) == expected[name], f"Frozen checksum: {name}")
    files["SHA256SUMS.txt"] = checksum_bytes
    expected["SHA256SUMS.txt"] = digest(checksum_bytes)
    manifest = json.loads(files["manifest.json"])
    require(manifest["version"] == VERSION, "Frozen manifest version mismatch")
    require(not manifest["runtimeScreenshotsIncluded"], "Runtime screenshots in gallery")
    for item in manifest["svgSources"]:
        require(files[item["copy"]] == frozen_bytes(item["source"]),
                f"Gallery source copy: {item['copy']}")
    require({item["path"] for item in manifest["previews"]} == PREVIEW_PATHS
            and len(manifest["previews"]) == len(PREVIEW_PATHS), "Expected the seven approved artwork previews")
    for item in manifest["previews"]:
        preview, source = files[item["path"]], frozen_bytes(item["source"])
        require(digest(preview) == item["sha256"] and len(preview) == item["bytes"],
                f"Preview metadata: {item['path']}")
        if "sourceSha256" in item:
            require(digest(source) == item["sourceSha256"], f"Preview vector source: {item['path']}")
        else:
            require(preview == source, f"Unchanged approved preview: {item['path']}")
    return files, expected, manifest


class PublicRedirectsOnly(urllib.request.HTTPRedirectHandler):
    def __init__(self, allowed_prefix):
        super().__init__()
        self.allowed_prefix = allowed_prefix

    def redirect_request(self, request, fp, code, message, headers, new_url):
        require(new_url.startswith(self.allowed_prefix), f"Unexpected public redirect: {new_url}")
        return super().redirect_request(request, fp, code, message, headers, new_url)


def public_get(url, allowed_prefix=SITE):
    # No keychain, netrc, cookies, Authorization header or proxy credentials.
    # A separate opener per request also avoids shared mutable cookie state.
    for attempt in range(1, 5):
        try:
            opener = urllib.request.build_opener(
                urllib.request.ProxyHandler({}), PublicRedirectsOnly(allowed_prefix)
            )
            request = urllib.request.Request(url, headers={
                "User-Agent": "Wattson-public-release-verification/5.0.2",
                "Accept": "*/*",
                "Cache-Control": "no-cache",
            })
            with opener.open(request, timeout=25) as response:
                require(response.status == 200, f"HTTP {response.status}: {url}")
                final_url = response.geturl()
                require(final_url.startswith(allowed_prefix), f"Unexpected final URL: {final_url}")
                data = response.read()
                return data, {"url": url, "finalURL": final_url, "status": 200,
                              "contentType": response.headers.get("Content-Type", ""),
                              "sha256": digest(data), "bytes": len(data), "attempts": attempt}
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == 4:
                raise
            time.sleep(attempt)


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = set()

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self.hrefs.add(href)


def main():
    global FROZEN_SHA
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sha", required=True, help="Full frozen release commit SHA")
    parser.add_argument("--source-only", action="store_true", help="No network or output file")
    parser.add_argument("--pages-confirmed-success", action="store_true")
    parser.add_argument("--pages-head-sha")
    parser.add_argument("--pages-run-id")
    parser.add_argument("--output", type=Path, help="New final JSON file; existing files are preserved")
    args = parser.parse_args()
    require(re.fullmatch(r"[0-9a-f]{40}", args.source_sha), "Explicit full frozen source SHA required")
    FROZEN_SHA = args.source_sha
    files, expected, manifest = load_frozen()
    source_zips = validate_zip_masters(files, manifest)
    if args.source_only:
        require(args.output is None, "--source-only writes no proof file")
        print(json.dumps({"acceptedPublicVerification": False, "networkReads": 0,
                          "frozenSHA": FROZEN_SHA, "checksummedResources": len(expected) - 1,
                          "sourcePackages": source_zips}, indent=2))
        return
    require(args.pages_confirmed_success, "Wait for coordinator's Pages-success confirmation")
    require(args.pages_head_sha == FROZEN_SHA, "Pages head SHA must equal the frozen source")
    require(args.pages_run_id and re.fullmatch(r"\d+", args.pages_run_id), "Pages run ID required")
    require(args.output is not None and not args.output.exists(), "Choose a new final proof path")
    evidence_root = (ROOT / "design/release-v5.0.2").resolve()
    require(args.output.resolve().is_relative_to(evidence_root), "Proof must remain in release evidence")
    remote_files = {}
    resources = []

    def verify(name):
        url = GALLERY + urllib.parse.quote(name, safe="/")
        data, details = public_get(url)
        require(digest(data) == expected[name], f"Public/frozen hash mismatch: {url}")
        return name, data, details

    # Every frozen gallery file, including the checksum manifest itself.
    with ThreadPoolExecutor(max_workers=4) as executor:
        for name, data, details in executor.map(verify, sorted(expected)):
            remote_files[name] = data
            resources.append({"path": name, **details, "matchesFrozenSource": True})
    public_zips = validate_zip_masters(remote_files, manifest)
    main_data, main_details = public_get(SITE)
    main_html = main_data.decode()
    links = Links()
    links.feed(main_html)
    asset_base = f"https://github.com/laleoarrow/battery-monitor/releases/download/v{VERSION}/"
    downloads = [asset_base + f"Wattson-v{VERSION}-macos-universal.{ext}" for ext in ("dmg", "pkg")]
    require(all(url in links.hrefs for url in downloads), "Main site lacks exact 5.0.2 PKG/DMG URLs")
    require(f"v{VERSION}" in main_html, "Main site version missing")
    require(not re.search(r"<script\b", main_html, re.I), "Pages site unexpectedly needs scripts")
    public_installer_links = [url for url in links.hrefs if re.search(r"/releases/download/.+\.(?:pkg|dmg)$", url)]
    require(set(public_installer_links) == set(downloads), "Main site contains stale installer links")
    latest_data, latest_details = public_get(LATEST_API, LATEST_API)
    latest = json.loads(latest_data)
    require(latest["tag_name"] == f"v{VERSION}", "Anonymous Latest release version mismatch")
    require(latest["draft"] is False and latest["prerelease"] is False,
            "Anonymous Latest is not a stable public release")
    require(latest["html_url"] == f"https://github.com/laleoarrow/battery-monitor/releases/tag/v{VERSION}",
            "Anonymous Latest release URL mismatch")
    proof = {
        "acceptedPublicVerification": True,
        "verifiedAtUTC": datetime.now(timezone.utc).isoformat(),
        "version": VERSION, "frozenSourceSHA": FROZEN_SHA,
        "pagesSuccessConfirmedByCoordinator": True, "pagesRunID": args.pages_run_id,
        "pagesHeadSHA": args.pages_head_sha,
        "credentialFreeRequests": True, "authorizationOrCookieHeadersSent": False,
        "galleryURL": GALLERY, "checksummedResourcesVerified": len(expected) - 1,
        "checksumManifestAlsoVerified": True,
        "resources": resources, "sourcePackages": public_zips,
        "exactFrozenSVGMastersVerified": sum(SVG_FAMILIES.values()),
        "mainSite": {**main_details, "exactVersionDownloadURLs": downloads,
                     "noStaleInstallerLinks": True, "serverIndependentHTML": True},
        "anonymousLatestRelease": {**latest_details, "tagName": latest["tag_name"],
                                   "htmlURL": latest["html_url"], "draft": latest["draft"],
                                   "prerelease": latest["prerelease"],
                                   "publishedAt": latest.get("published_at")},
        "externalMutations": 0, "temporaryFilesCreated": 0,
    }
    with args.output.open("x") as output:
        output.write(json.dumps(proof, indent=2) + "\n")
    print(json.dumps({"acceptedPublicVerification": True, "proof": str(args.output),
                      "galleryResources": len(expected), "exactFrozenSVGMasters": sum(SVG_FAMILIES.values()),
                      "mainSiteVersion": VERSION}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"acceptedPublicVerification": False, "error": str(error)}), file=sys.stderr)
        sys.exit(1)
