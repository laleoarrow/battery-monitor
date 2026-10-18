#!/usr/bin/env python3
"""Audit v4.3.22 AFTER its tag, release assets and Pages gallery are public.

Anonymous, read-only HTTP and git reads only. Downloads stay in memory, no
credentials or cookies are loaded, and the JSON report is written to stdout.
Run from any directory; redirect stdout to a caller-owned evidence file if wanted.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urljoin
from urllib.request import Request, build_opener, HTTPRedirectHandler, HTTPSHandler, ProxyHandler

ROOT = Path(__file__).resolve().parents[3]
FROZEN = "7f41533b017d26519a69d541d3ffd2dea587f413"
TAG = "v4.3.22"
REPO = "https://github.com/laleoarrow/battery-monitor"
RAW = f"https://raw.githubusercontent.com/laleoarrow/battery-monitor/{TAG}/"
GALLERY_PATH = f"design/releases/{TAG}/"
PAGES = f"https://laleoarrow.github.io/battery-monitor/design/{TAG}/"
ASSETS = f"{REPO}/releases/download/{TAG}/"


class GalleryLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.ids = set(), set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        self.links.update(attrs[k] for k in ("href", "src") if k in attrs)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def frozen_file(relative):
    data = subprocess.check_output(["git", "show", f"{FROZEN}:{relative}"], cwd=ROOT)
    assert (ROOT / relative).read_bytes() == data, f"Local file differs from frozen source: {relative}"
    return data


def request(url, method="GET"):
    # Explicit handlers exclude environment proxies, cookie jars and auth handlers.
    opener = build_opener(ProxyHandler({}), HTTPRedirectHandler(), HTTPSHandler())
    opener.addheaders = []
    req = Request(url, method=method, headers={
        "User-Agent": "Wattson-public-gallery-audit/4.3.22",
        "Accept": "application/json" if "api.github.com" in url else "*/*",
        "Cache-Control": "no-cache",
    })
    with opener.open(req, timeout=30) as response:
        assert response.status == 200, f"HTTP {response.status}: {url}"
        data = b"" if method == "HEAD" else response.read(8 * 1024 * 1024 + 1)
        assert len(data) <= 8 * 1024 * 1024, f"Unexpectedly large design response: {url}"
        return data, response.geturl().split("?", 1)[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local-only", action="store_true", help="Validate frozen/local references without HTTP")
    args = parser.parse_args()
    manifest = json.loads(frozen_file(GALLERY_PATH + "manifest.json"))
    assert manifest["version"] == TAG[1:] and not manifest["runtimeScreenshotsIncluded"]
    assert [p["runtimeMasterCount"] for p in manifest["sourcePackages"]] == [6, 3, 5, 5]
    assert len(manifest["previews"]) == 9 and len(manifest["svgSources"]) == 19
    notes = frozen_file(f"docs/releases/{TAG}/release-notes.md").decode()
    urls = set(re.findall(r"https://[^\s)]+", notes))
    assert PAGES in urls and f"{REPO}/tree/{TAG}/{GALLERY_PATH.rstrip('/')}" in urls
    tasks = {}
    for record in manifest["previews"] + manifest["sourcePackages"] + manifest["svgSources"]:
        relative = record.get("path", record.get("copy"))
        data = frozen_file(GALLERY_PATH + relative)
        assert sha(data) == record["sha256"], f"Manifest hash mismatch: {relative}"
    for record in manifest["renderInputs"]:
        assert sha(frozen_file(record["path"])) == record["sha256"]
    for line in frozen_file(GALLERY_PATH + "SHA256SUMS.txt").decode().splitlines():
        checksum, relative = line.split("  ", 1)
        assert sha(frozen_file(GALLERY_PATH + relative)) == checksum, relative
    html = frozen_file(GALLERY_PATH + "index.html")
    links = GalleryLinks()
    links.feed(html.decode())
    for link in links.links:
        if link.startswith("#"):
            assert link[1:] in links.ids, f"Broken anchor: {link}"
        elif not link.startswith("https:"):
            tasks[urljoin(PAGES, link)] = ("GET", sha(frozen_file(GALLERY_PATH + link)))
    tasks[PAGES] = ("GET", sha(html))
    for record in manifest["previews"]:
        tasks[RAW + GALLERY_PATH + record["path"]] = ("GET", record["sha256"])
    for record in manifest["sourcePackages"]:
        url = ASSETS + record["path"]
        assert url in urls, f"SVG package absent from release notes: {url}"
        tasks[url] = ("GET", record["sha256"])
    for url in urls:
        if url.startswith(RAW):
            relative = url.removeprefix(RAW)
            tasks[url] = ("GET", sha(frozen_file(relative)))
    installers = [f"Wattson-{TAG}-macos-universal.{suffix}" for suffix in ("pkg", "dmg")]
    for name in installers:
        assert ASSETS + name in urls, f"Installer link absent from release notes: {name}"
        tasks[ASSETS + name] = ("HEAD", None)
    report = {"version": TAG, "frozenCommit": FROZEN, "anonymous": True,
              "checkedAtUTC": datetime.now(timezone.utc).isoformat(),
              "localReferences": "pass", "remoteRequested": not args.local_only,
              "sourcePackages": 4, "svgMasters": 19, "previews": 9, "checks": [], "failures": []}
    if not args.local_only:
        release_url = f"https://api.github.com/repos/laleoarrow/battery-monitor/releases/tags/{TAG}"
        try:
            body, final = request(release_url)
            release = json.loads(body)
            assert release["tag_name"] == TAG and not release["draft"] and not release["prerelease"]
            asset_names = {a["name"] for a in release["assets"]}
            assert set(installers + [f"Wattson-{TAG}-release-info.txt", "SHA256SUMS.txt"]).issubset(asset_names)
            assert {p["path"] for p in manifest["sourcePackages"]}.issubset(asset_names)
            for url in urls:
                assert url in release["body"], f"Frozen note link absent from published body: {url}"
            for disclosure in ("ad-hoc", "未签名", "未公证", "Gatekeeper"):
                assert disclosure in release["body"], f"Missing signing disclosure: {disclosure}"
            report["checks"].append({"url": release_url, "finalUrl": final, "kind": "public-release", "ok": True})
        except Exception as error:
            report["failures"].append({"url": release_url, "error": str(error)})
        def audit(item):
            url, (method, expected) = item
            try:
                data, final = request(url, method)
                actual = sha(data) if method == "GET" else None
                assert expected is None or actual == expected, f"SHA256 mismatch: expected {expected}, got {actual}"
                return {"url": url, "finalUrl": final, "method": method, "sha256": actual, "ok": True}
            except Exception as error:
                return {"url": url, "error": str(error), "ok": False}
        with ThreadPoolExecutor(max_workers=4) as pool:
            for result in pool.map(audit, sorted(tasks.items())):
                report["checks" if result["ok"] else "failures"].append(result)
    report["ok"] = not report["failures"]
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(json.dumps({"ok": False, "stage": "local-preflight", "error": str(error)}, indent=2))
        sys.exit(1)
