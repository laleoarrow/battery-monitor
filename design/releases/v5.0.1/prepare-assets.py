#!/usr/bin/env python3
"""Copy approved artwork and deterministically package the release's SVG masters.

All outputs are final gallery assets in this script's directory; no app,
registration, preference, compiler cache, mount, or temporary file is created.
"""
import hashlib
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[3]
DEST = Path(__file__).resolve().parent
VERSION = "5.0.1"
assert (ROOT / "VERSION").read_text().strip() == VERSION
FAMILIES = {
    "Modules": ("design/settings/module-icons-vector", 6),
    "Sidebar": ("design/settings/sidebar-icons-vector", 3),
    "General": ("design/settings/general-icons-vector", 5),
    "Power": ("design/popover/power-icons-vector", 5),
}
PREVIEWS = [
    "design/settings/module-icons-vector/vector-preview.png",
    "design/settings/sidebar-icons-vector/sidebar-vector-preview.png",
    "design/settings/general-icons-vector/general-vector-preview.png",
    "design/popover/power-icons-vector/power-vector-preview.png",
    "design/popover/power-icons-vector/power-state-matrix.png",
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


sources = []
packages = []
for family, (relative, count) in FAMILIES.items():
    folder = DEST / "svg" / family.lower()
    folder.mkdir(parents=True, exist_ok=True)
    masters = sorted((ROOT / relative).glob("*.svg"))
    assert len(masters) == count, (family, len(masters))
    for path in masters:
        tree = ET.fromstring(path.read_bytes())
        for node in tree.iter():
            assert node.tag.split("}")[-1] not in {"image", "script", "foreignObject", "text"}
            for key, value in node.attrib.items():
                assert not key.split("}")[-1].startswith("on")
                if key.split("}")[-1] == "href":
                    assert value.startswith("#")
        target = folder / path.name
        shutil.copyfile(path, target)
        assert digest(path) == digest(target)
        sources.append({"source": relative + "/" + path.name,
                        "copy": str(target.relative_to(DEST)), "sha256": digest(path),
                        "bytes": path.stat().st_size})
    (folder / "README.txt").write_text(
        f"Wattson {VERSION} — {family} editable SVG originals\n"
        f"{count} approved runtime SVG masters, copied byte-for-byte from the release source.\n"
        "Transparent vector artboards; no raster images or external resources.\n"
        "Runtime appearance/state colors are supplied by native AppKit paths; SVG blue is an accent placeholder.\n"
        "Previews and provenance: https://laleoarrow.github.io/battery-monitor/design/v5.0.1/\n",
        encoding="utf-8")
    package = DEST / f"Wattson-v{VERSION}-{family}-SVG.zip"
    with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(folder.iterdir()):
            info = zipfile.ZipInfo(f"Wattson-v{VERSION}-{family}-SVG/{path.name}", (2026, 10, 20, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None
    packages.append({"path": package.name, "sha256": digest(package),
                     "bytes": package.stat().st_size, "runtimeMasterCount": count})

(DEST / "previews").mkdir(exist_ok=True)
previews = []
for relative in PREVIEWS:
    source = ROOT / relative
    target = DEST / "previews" / source.name
    shutil.copyfile(source, target)
    assert digest(source) == digest(target)
    previews.append({"path": str(target.relative_to(DEST)), "source": relative,
                     "sha256": digest(target), "bytes": target.stat().st_size,
                     "method": "Existing approved native offscreen artwork proof, copied unchanged; no running-app screenshot"})
manifest = {
    "schema": 1, "version": VERSION,
    "presentation": "Approved icon design previews and native offscreen artwork proofs",
    "runtimeScreenshotsIncluded": False,
    "iconArtworkReusedUnchanged": True,
    "artworkScope": "Retained approved Settings and Power icon proofs. These images illustrate the included artwork, not the new process-whitelist interface, performance changes or live battery readings.",
    "svgSources": sources, "sourcePackages": packages, "previews": previews,
    "installerAssetContractUnchanged": True,
}
(DEST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
paths = [p for p in sorted(DEST.rglob("*")) if p.is_file() and p.name != "SHA256SUMS.txt"]
(DEST / "SHA256SUMS.txt").write_text("".join(f"{digest(p)}  {p.relative_to(DEST)}\n" for p in paths))
print(json.dumps({"packages": packages, "previews": len(previews),
                  "svgMasters": sum(v[1] for v in FAMILIES.values())}, indent=2))
