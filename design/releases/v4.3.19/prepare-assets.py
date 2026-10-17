#!/usr/bin/env python3
"""Freeze current editable masters and make deterministic versioned design ZIPs."""
import hashlib
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[3]
DEST = Path(__file__).resolve().parent
VERSION = "4.3.19"
assert (ROOT / "VERSION").read_text().strip() == VERSION
FAMILIES = {
    "Modules": ("design/settings/module-icons-vector", 6),
    "Sidebar": ("design/settings/sidebar-icons-vector", 3),
    "General": ("design/settings/general-icons-vector", 5),
    "Power": ("design/popover/power-icons-vector", 5),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


source_records = []
zip_records = []
for family, (relative, count) in FAMILIES.items():
    folder = DEST / "svg" / family.lower()
    folder.mkdir(parents=True, exist_ok=True)
    masters = sorted((ROOT / relative).glob("*.svg"))
    assert len(masters) == count, (family, len(masters))
    sources = masters
    if family == "Power":
        sources += sorted((ROOT / relative / "source").glob("pro-b-*.svg"))
        sources += [ROOT / relative / "source/normalization.json"]
    for path in sources:
        if path.suffix == ".svg":
            tree = ET.fromstring(path.read_bytes())
            for node in tree.iter():
                assert node.tag.split("}")[-1] not in {"image", "script", "foreignObject", "text"}
                for key, value in node.attrib.items():
                    assert not key.split("}")[-1].startswith("on")
                    if key.split("}")[-1] == "href":
                        assert value.startswith("#")
        name = path.name if path.parent == ROOT / relative else "source/" + path.name
        target = folder / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        assert digest(path) == digest(target)
        source_records.append({"source": str(path.relative_to(ROOT)), "copy": str(target.relative_to(DEST)),
                               "sha256": digest(path), "bytes": path.stat().st_size})
    (folder / "README.txt").write_text(
        f"Wattson {VERSION} — {family} editable SVG originals\n"
        f"{count} runtime SVG masters, copied byte-for-byte from the release source.\n"
        "Transparent vector artboards; no raster images or external resources.\n"
        "The Power family also retains the two original Pro design SVGs and normalization record.\n"
        "Previews and provenance: https://laleoarrow.github.io/battery-monitor/design/v4.3.19/\n",
        encoding="utf-8")
    package = DEST / f"Wattson-v{VERSION}-{family}-SVG.zip"
    with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(folder.rglob("*")):
            if not path.is_file():
                continue
            info = zipfile.ZipInfo(f"Wattson-v{VERSION}-{family}-SVG/{path.relative_to(folder)}", (2026, 10, 17, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None
    zip_records.append({"path": package.name, "sha256": digest(package), "bytes": package.stat().st_size,
                        "runtimeMasterCount": count})

inputs = [ROOT / "Popover/TopProcessesView.swift", ROOT / "MenuBar/ModuleIconArtwork.swift",
          ROOT / "design/settings/module-icons-vector/render-preview.swift",
          ROOT / "design/popover/power-icons-vector/render-preview.swift",
          DEST / "render-process-preview.swift"]
manifest = {
    "schema": 1, "version": VERSION, "presentation": "Approved design previews and native offscreen renders",
    "runtimeScreenshotsIncluded": False, "illustrativeProcessScores": [84, 46, 8.1],
    "processMetric": "CPU usage and idle wakeups combined into an activity score, not measured power consumption",
    "gradient": "Fixed 0–100 horizontal light-blue to dark-blue scale, clipped at the value",
    "renderInputs": [{"path": str(p.relative_to(ROOT)), "sha256": digest(p)} for p in inputs],
    "svgSources": source_records, "sourcePackages": zip_records,
    "previews": [{"path": str(p.relative_to(DEST)), "sha256": digest(p), "bytes": p.stat().st_size,
                  "method": "Native offscreen render; no window or app screenshot"}
                 for p in sorted((DEST / "previews").glob("*.png"))],
    "installerAssetContractUnchanged": True,
}
assert len(manifest["previews"]) == 9
(DEST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
paths = [p for p in sorted(DEST.rglob("*")) if p.is_file() and p.name != "SHA256SUMS.txt"]
(DEST / "SHA256SUMS.txt").write_text("".join(f"{digest(p)}  {p.relative_to(DEST)}\n" for p in paths))
print(json.dumps({"packages": zip_records, "previews": len(manifest["previews"]),
                  "svgMasters": sum(v[1] for v in FAMILIES.values())}, indent=2))
