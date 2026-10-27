"""Bind the audited read-only 5.0.2 verifier to exact accepted public PKG bytes."""
import sys

sys.dont_write_bytecode = True
if sys.flags.optimize:
    raise SystemExit("Run without Python optimization.")

from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PUBLICATION = ROOT / "design/release-v5.0.2/publication"
PUBLIC_ASSETS = ROOT / "dist/public-v5.0.2-verify"
VERSION = "5.0.2"
NAMES = {"SHA256SUMS.txt", "Wattson-v5.0.2-macos-universal.pkg",
         "Wattson-v5.0.2-macos-universal.dmg", "Wattson-v5.0.2-release-info.txt"}
spec = importlib.util.spec_from_file_location(
    "wattson_local_install_verifier", ROOT / "design/battery-time-indicator/installation/installation_state.py"
)
local = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local)
require, digest = local.require, local.canonical.digest
base_identity, base_baseline = local.identity, local.baseline
base_write = local.canonical.write_new


def public_contract(package, source):
    package = Path(package)
    provenance_path = PUBLICATION / "artifact-public-provenance.json"
    require(package == PUBLIC_ASSETS / f"Wattson-v{VERSION}-macos-universal.pkg"
            and not PUBLIC_ASSETS.is_symlink(), "Use the exact retained anonymously verified public PKG")
    require(provenance_path.is_file() and not provenance_path.is_symlink(), "Public provenance is required")
    public = json.loads(provenance_path.read_text())
    require(public["version"] == VERSION and public["sourceCommit"] == source,
            "Public package source/version mismatch")
    require(all(public[field] is True for field in (
        "publicAssetsMatchCandidate", "packageVerified", "anonymousDownload", "strictThreeEntryManifest")),
        "Complete anonymous public verification is required")
    require(Path(public["publicAssetDirectory"]) == PUBLIC_ASSETS
            and set(public["files"]) == NAMES
            and {p.name for p in PUBLIC_ASSETS.iterdir()} == NAMES, "Public four-file set mismatch")
    proof_path = Path(public["candidateProof"])
    run = public["candidateRunID"]
    require(type(run) is int and run > 0 and proof_path.parent.parent == PUBLICATION
            and proof_path.parent.name.startswith(f"artifact-{run}-review.")
            and proof_path.name == "artifact-proof.json" and not proof_path.is_symlink()
            and not proof_path.parent.is_symlink(), "Wrong accepted candidate proof path")
    require(digest(proof_path) == public["candidateProofSHA256"], "Accepted candidate proof changed")
    proof = json.loads(proof_path.read_text())
    require(proof["candidate_checks_passed"] is True and proof["run_id"] == run
            and proof["source_sha"] == source and proof["version"] == VERSION, "Candidate proof identity mismatch")
    for name, expected in proof["evidence_sha256"].items():
        require(digest(proof_path.parent / name) == expected, "Candidate evidence changed")
    for marker in (proof_path.parent / "artifact-workspace.txt", PUBLICATION / "artifact-public-workspace.txt"):
        scratch = marker.read_text().strip()
        require(scratch and not Path(scratch).exists(), "Publication verification cleanup is incomplete")
    expected_files = json.loads((proof_path.parent / "artifact-download.json").read_text())["files"]
    require(set(expected_files) == NAMES, "Candidate file set mismatch")
    for name, item in public["files"].items():
        path = PUBLIC_ASSETS / name
        require(path.is_file() and not path.is_symlink() and item["cmpToCandidate"] is True
                and digest(path) == item["sha256"] == expected_files[name]["sha256"]
                and path.stat().st_size == item["bytes"] == expected_files[name]["bytes"],
                "Verified public bytes changed")
    require(digest(package) == public["packageSHA256"], "Public package digest mismatch")
    return {"provenancePath": str(provenance_path), "provenanceSHA256": digest(provenance_path),
            "candidateProofSHA256": public["candidateProofSHA256"], "candidateRunID": run,
            "releaseID": public["releaseID"], "anonymousDownload": True,
            "exactAcceptedPublicBytes": True, "publicationCleanupCompleted": True}


def public_identity(package, source):
    result = base_identity(package, source)
    public_contract(package, source)
    return result


def public_baseline(package, source, before_path):
    result = base_baseline(package, source, before_path)
    before = result[1]
    require(before["publicRelease"] is True
            and before["publicPackageVerification"] == public_contract(package, source),
            "Baseline public verification identity changed")
    return result


def write_public(path, record):
    contract = public_contract(record["packagePath"], record["sourceCommit"])
    if "publicPackageVerification" in record:
        require(record["publicPackageVerification"] == contract, "Staged public verification changed")
    base_write(path, {**record, "publicRelease": True, "publicPackageVerification": contract})


def main():
    # Reuse every canonical snapshot, setting, receipt and post-cleanup check.
    # Only the identity/baseline/writer boundaries add public-byte provenance.
    local.identity, local.baseline = public_identity, public_baseline
    local.canonical.write_new = write_public
    mode = sys.argv[1]
    if mode == "finalize":
        stage = json.loads(Path(sys.argv[2]).read_text())
        require(stage["publicRelease"] is True, "Expected a public-install staged result")
    with redirect_stdout(io.StringIO()):
        local.main()
    if mode == "before":
        print("PUBLIC_INSTALL_BASELINE_RECORDED")
    elif mode == "finalize":
        print("CANONICAL_PUBLIC_INSTALL_VERIFIED")


if __name__ == "__main__":
    main()
