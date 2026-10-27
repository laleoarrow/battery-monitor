#!/usr/bin/env python3
"""Record static candidate proof; shared Bash owner still performs EXIT cleanup."""
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]


def main():
    sha = os.environ.get("WATTSON_RELEASE_SOURCE_SHA", "")
    if re.fullmatch(r"[0-9a-f]{40}", sha) is None:
        raise ValueError("Expected explicit frozen source SHA")
    if len(sys.argv) != 4 or re.fullmatch(r"[1-9][0-9]+", sys.argv[3]) is None:
        raise ValueError("Usage: artifact-proof.py RECORD-DIRECTORY FINAL-ASSETS RUN-ID")
    record, final = map(lambda value: Path(value).resolve(), sys.argv[1:3])
    run = int(sys.argv[3])
    if (record.parent != Path(__file__).resolve().parent
            or not record.name.startswith(f"artifact-{run}-review.")
            or final != ROOT / "dist" / f"github-candidate-v5.0.2-{run}"):
        raise ValueError("Proof paths must match this candidate invocation")
    before = json.loads((record / "artifact-before.json").read_text())
    after = json.loads((record / "artifact-after.json").read_text())
    signatures = json.loads((record / "artifact-signatures.json").read_text())
    download = json.loads((record / "artifact-download.json").read_text())
    if (before["status"] != "passed" or after["status"] != "passed"
            or signatures["status"] != "passed"
            or before["canonical_files"] != after["canonical_files"]
            or before["receipt"] != after["receipt"]
            or download["run_id"] != run or download["source_sha"] != sha):
        raise ValueError("Candidate proof inputs failed or canonical installed files changed")
    proof = {
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "run_id": run, "source_sha": sha, "version": "5.0.2",
        "candidate_checks_passed": True,
        "canonical_files_and_receipt_unchanged": True,
        "retained_exact_assets": str(final),
        "cleanup_scope": "Shared EXIT lifecycle must finish successfully; no independent whole-host cleanup census is claimed.",
        "evidence_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in record.iterdir() if p.is_file()},
    }
    with (record / "artifact-proof.json").open("x") as output:
        json.dump(proof, output, indent=2, sort_keys=True)
        output.write("\n")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError):
        print("artifact-proof: candidate proof inputs invalid or evidence already exists", file=sys.stderr)
        sys.exit(1)
