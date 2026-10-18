#!/usr/bin/env python3
"""Use the previously validated anonymous public REST/CDN transport."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import importlib.util
import json
import shutil
import sys
import time
import urllib.error
import urllib.request

spec = importlib.util.spec_from_file_location("public_contract", Path(__file__).with_name("artifact-public-download-v4.3.22.py"))
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def read_bounded(response, count):
    deadline, payload = time.monotonic() + 25, bytearray()
    while len(payload) <= count:
        contract.require(time.monotonic() <= deadline, "Anonymous response exceeded elapsed bound")
        data = response.read1(min(16384, count + 1 - len(payload)))
        if not data:
            break
        payload.extend(data)
    contract.require(len(payload) == count, "Anonymous response length mismatch")
    return bytes(payload)

def download(asset, private, output):
    api = "https://api.github.com/repos/laleoarrow/battery-monitor/releases/assets/" + str(asset["id"])
    contract.require(asset["url"] == api, "Unexpected anonymous REST asset origin")
    headers = {"Accept": "application/octet-stream", "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "Wattson-public-release-verification"}
    response, redirect = None, None
    try:
        response = urllib.request.build_opener(NoRedirect()).open(urllib.request.Request(api, headers=headers), timeout=15)
    except urllib.error.HTTPError as error:
        contract.require(error.code == 302, "Anonymous public API HTTP " + str(error.code))
        redirect = error.headers.get("Location", "")
        parsed = contract.urlparse(redirect)
        contract.require(parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password
                         and not any(c in redirect for c in "\r\n"), "Unsafe anonymous public CDN redirect")
        error.close()
    if asset["size"] < 1024:
        if response is None:
            response = urllib.request.build_opener(NoRedirect()).open(urllib.request.Request(redirect), timeout=10)
        with response:
            contract.require(response.status == 200, "Anonymous public text status mismatch")
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
            contract.require(reply.status == 206 and reply.headers.get("Content-Range") == "bytes " + str(begin) + "-" + str(end) + "/" + str(total), "Anonymous public CDN range boundary mismatch")
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
        contract.require(len(payload) == end - begin + 1, "Anonymous public assembled range length mismatch")
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

if __name__ == "__main__":
    try:
        contract.download = download
        contract.main()
        proof = contract.EVIDENCE / "artifact-public-download-v4.3.22.json"
        record = json.loads(proof.read_text())
        record["authentication"] = "Anonymous public REST asset API and CDN via urllib; no gh, token, Authorization header, cookies or netrc; default TLS verification"
        record["transport"] = "Previously validated public REST 302/CDN route; 256 KiB ranges, eight workers per installer, one bounded half-range split retry"
        proof.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    except Exception as error:
        print("artifact-public-urllib: " + (str(error) if isinstance(error, RuntimeError) else "Anonymous transfer failed (" + type(error).__name__ + ")"), file=sys.stderr)
        sys.exit(1)
