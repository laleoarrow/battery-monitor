#!/usr/bin/env python3
"""Copy approved artwork and deterministically package the release's SVG masters.

All outputs are final gallery assets in this script's directory; no app,
registration, preference, compiler cache, mount, or temporary file is created.
"""
import hashlib
import json
from pathlib import Path
import shutil
import math
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[3]
DEST = Path(__file__).resolve().parent
VERSION = "5.0.3"
assert (ROOT / "VERSION").read_text().strip() == VERSION
FAMILIES = {
    "Modules": ("design/settings/module-icons-vector", 6),
    "Sidebar": ("design/settings/sidebar-icons-vector", 3),
    "General": ("design/settings/general-icons-vector", 5),
    "Power": ("design/popover/power-icons-vector", 6),
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


def time_preview(theme):
    """Approved design composition; this is vector artwork, not an App screenshot."""
    dark = theme == "dark"
    bg, surface, ink, muted, line, well = (("#19191d", "#242428", "#f2f2f7", "#aaaab4", "#414149", "#303036")
        if dark else ("#f6f6f8", "#ffffff", "#222228", "#65656d", "#d5d5dc", "#e5e5eb"))
    neutral, green, blue, red = (("#c7c7cc", "#30d158", "#0a84ff", "#ff453a")
        if dark else ("#565662", "#18783a", "#0064cf", "#c72528"))
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1040" viewBox="0 0 1200 1040" role="img" aria-labelledby="title desc">',
        '<title id="title">Wattson 5.0.3 时间来源与渐变时钟设计预览</title>',
        '<desc id="desc">系统值恒亮，备用估算缓慢呼吸，计算中呼吸与星轨同步，无法计算时红色脉动。批准的矢量设计放大图，非App运行截图。</desc>',
        f'<rect width="1200" height="1040" fill="{bg}"/>',
        '<g font-family="-apple-system,BlinkMacSystemFont,PingFang SC,Helvetica Neue,sans-serif">']
    def text(x, y, value, size=20, color=muted, weight=400, anchor="start"):
        svg.append(f'<text x="{x}" y="{y}" fill="{color}" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}">{value}</text>')
    def clock(x, y, accent, identity, size=64):
        master = (ROOT / "design/popover/power-icons-vector/clock.svg").read_text()
        body = master[master.index(">")+1:master.rindex("</svg>")]
        body = body.replace('<title>Wattson Battery time clock</title>', "")
        body = body.replace('id="face"', f'id="face-{identity}"').replace("url(#face)", f"url(#face-{identity})")
        body = body.replace("#0A84FF", accent).replace("currentColor", neutral)
        svg.append(f'<rect x="{x}" y="{y}" width="{size}" height="{size}" rx="16" fill="{well}" stroke="{accent}" stroke-opacity=".34"/>')
        image_size = size * 24 / 44
        inset = (size-image_size)/2
        svg.append(f'<svg x="{x+inset}" y="{y+inset}" width="{image_size}" height="{image_size}" viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round">{body}</svg>')
    def planet(x, y, accent, identity, orbit=False, opacity=1):
        rgb = [int(accent[k:k+2], 16) for k in (1, 3, 5)]
        bright = "#" + "".join(f"{round(c*.35+255*.65):02x}" for c in rgb)
        deep = "#" + "".join(f"{round(c*.82):02x}" for c in rgb)
        svg.append(f'<defs><radialGradient id="planet-{identity}" cx="30%" cy="25%"><stop stop-color="{bright}"/><stop offset=".48" stop-color="{accent}"/><stop offset="1" stop-color="{deep}"/></radialGradient><radialGradient id="halo-{identity}"><stop stop-color="{accent}" stop-opacity=".30"/><stop offset=".35" stop-color="{accent}" stop-opacity=".13"/><stop offset=".72" stop-color="{accent}" stop-opacity="0"/></radialGradient></defs>')
        svg.append(f'<circle cx="{x}" cy="{y}" r="16" fill="url(#halo-{identity})" opacity="{opacity}"/><circle cx="{x}" cy="{y}" r="6.4" fill="url(#planet-{identity})" opacity="{opacity}"/>')
        if orbit:
            for i in range(7, -1, -1):
                angle = math.pi - i*.13
                px, py = 8.5*math.cos(angle), 4.6*math.sin(angle)
                tilt = -math.pi/5
                xx = x + 1.6*(px*math.cos(tilt)-py*math.sin(tilt))
                yy = y + 1.6*(px*math.sin(tilt)+py*math.cos(tilt))
                radius = (1.9 if i == 0 else max(.45, 1.5-i*.15)) * .8
                alpha = 1 if i == 0 else .7*.72**(i-1)
                svg.append(f'<circle cx="{xx:.3f}" cy="{yy:.3f}" r="{radius:.3f}" fill="{bright if i == 0 else accent}" opacity="{alpha:.3f}"/>')
    text(48, 56, "WATTSON 5.0.3  /  设计预览", 18, muted, 600)
    text(1152, 56, "DARK" if dark else "LIGHT", 18, muted, 500, "end")
    text(48, 118, "看清时间，也看清来源。", 42, ink, 600)
    text(48, 162, "一颗光点，轻轻区分系统值、备用估算与计算中。", 23)
    states = [
        ("系统数据", "主题色恒亮", "4h 25m", "来自 macOS 的剩余时间", neutral, 1),
        ("备用估算", "缓慢呼吸", "≈4h 25m", "系统值暂缺时，显示备用估算", neutral, .72),
        ("计算中", "呼吸与星轨同步", "Calculating…", "立即绕行 · 一圈后歇 0.5 秒", neutral, 1),
        ("无法计算", "柔和红色脉动", "Unavailable", "当前数据不足以给出时间", red, .8),
    ]
    for i, (name, action, value, detail, accent, opacity) in enumerate(states):
        x, y = 48+(i%2)*564, 206+(i//2)*280
        svg.append(f'<rect x="{x}" y="{y}" width="540" height="252" rx="24" fill="{surface}" stroke="{line}"/>')
        text(x+28, y+44, name, 23, ink, 600)
        text(x+512, y+44, action, 17, muted, 400, "end")
        clock(x+28, y+91, neutral, i)
        planet(x+270, y+106, accent, i, orbit=i==2, opacity=opacity)
        text(x+512, y+112, "Estimated Battery Runtime", 19, muted, 400, "end")
        text(x+512, y+157, value, 36 if i<2 else 28, ink if i<2 else muted, 600 if i<2 else 400, "end")
        text(x+28, y+218, detail, 18)
    text(48, 812, "主题，自然相随", 25, ink, 600)
    text(48, 846, "光点、时钟与仪表共用配色。红色只用于无法计算的状态光点。", 20)
    for i, (name, accent) in enumerate([("电池 · 银灰",neutral),("充电 · 绿色",green),("接电 · 蓝色",blue)]):
        x = 48+i*376
        clock(x, 878, accent, f"palette-{i}", 52)
        planet(x+86, 904, accent, f"palette-{i}")
        text(x+114, 912, name, 21, ink, 500)
    svg.append(f'<path d="M48 966H1152" stroke="{line}"/>')
    text(48, 1003, "已批准 SVG 设计放大图 · 示例数值 · 非 App 运行截图", 18)
    text(1152, 1003, "wattson / 5.0.3", 18, muted, 400, "end")
    svg.append("</g></svg>")
    target = DEST / "previews" / f"time-source-{theme}.svg"
    target.parent.mkdir(exist_ok=True)
    target.write_text("\n".join(svg)+"\n")


def scrollbar_preview():
    """Retain the approved geometry; update its earlier default to the shipped Flow default."""
    source = (ROOT / "design/scrollbar-styles/scrollbar-style-preview.html").read_text()
    for old, new in [
        ('data-style="hidden"', 'data-style="flow"'),
        ('<option value="hidden" selected>', '<option value="hidden">'),
        ('<option value="flow">', '<option value="flow" selected>'),
        ("默认隐藏，仍可上下滚动。", "隐藏外观，仍可上下滚动。"),
        ("默认：隐藏", "默认：流光"),
        ("style:'hidden'", "style:'flow'"),
        ("defaultStyle:'hidden'", "defaultStyle:'flow'"),
    ]:
        assert old in source, old
        source = source.replace(old, new)
    (DEST / "scrollbar-preview.html").write_text(
        '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta name="color-scheme" content="light dark">'
        '<title>Wattson 5.0.3 Scrollbar Design Preview</title>'
        '<style>body{margin:0}</style></head><body>' + source + '</body></html>\n')


for theme in ("light", "dark"):
    time_preview(theme)
scrollbar_preview()
if "--svg-only" in sys.argv:
    print("Prepared Light/Dark vector design compositions; render each at 1200 x 1040 to its matching PNG.")
    raise SystemExit(0)

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
        "Previews and provenance: https://laleoarrow.github.io/battery-monitor/design/v5.0.3/\n",
        encoding="utf-8")
    package = DEST / f"Wattson-v{VERSION}-{family}-SVG.zip"
    with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(folder.iterdir()):
            info = zipfile.ZipInfo(f"Wattson-v{VERSION}-{family}-SVG/{path.name}", (2026, 10, 31, 0, 0, 0))
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
for theme in ("light", "dark"):
    source = DEST / "previews" / f"time-source-{theme}.svg"
    target = source.with_suffix(".png")
    assert target.is_file(), f"Render the approved SVG composition first: {target}"
    previews.append({"path": str(target.relative_to(DEST)), "source": str(source.relative_to(ROOT)),
                     "sourceSha256": digest(source), "sha256": digest(target), "bytes": target.stat().st_size,
                     "width": 1200, "height": 1040,
                     "method": "Browser-rendered approved SVG design composition; fixed example values; no running-app screenshot"})
# Newly approved versioned design assets are copied without re-encoding.
release_previews = [
    ("design/release-v5.0.3/gallery/full-charge-orbit.gif", "full-charge-orbit.gif"),
    ("design/release-v5.0.3/gallery/full-charge-orbit-poster.png", "full-charge-orbit-poster.png"),
    ("design/release-v5.0.3/gallery/full-charge-orbit-light.png", "full-charge-orbit-light.png"),
    ("design/release-v5.0.3/gallery/full-charge-orbit-dark.png", "full-charge-orbit-dark.png"),
]
for relative, name in release_previews:
    source = ROOT / relative
    target = DEST / "previews" / name
    shutil.copyfile(source, target)
    assert digest(source) == digest(target)
    previews.append({"path": str(target.relative_to(DEST)), "source": relative,
                     "sha256": digest(target), "bytes": target.stat().st_size,
                     "method": "Approved design animation or composition, copied unchanged; no running-app screenshot"})
for theme in ("light", "dark"):
    source = DEST / "scrollbar-preview.html"
    target = DEST / "previews" / f"scrollbar-flow-{theme}.png"
    assert target.is_file(), f"Render the versioned scrollbar preview first: {target}"
    previews.append({"path": str(target.relative_to(DEST)), "source": str(source.relative_to(ROOT)),
                     "sourceSha256": digest(source), "sha256": digest(target), "bytes": target.stat().st_size,
                     "method": "Browser-rendered approved scrollbar geometry with the shipped Flow default; no running-app screenshot"})
manifest = {
    "schema": 1, "version": VERSION,
    "presentation": "Approved full-charge animation, scrollbar and time-source designs, and native offscreen icon proofs",
    "runtimeScreenshotsIncluded": False,
    "retainedIconArtworkReusedUnchanged": True,
    "approvedTimeDesignSource": "design/battery-time-indicator/planet-source-preview.html",
    "approvedFullChargeDesignSource": "design/battery-time-indicator/full-charge/full-charge-preview.html",
    "approvedScrollbarDesignSource": "design/scrollbar-styles/scrollbar-style-preview.html",
    "fullChargeAnimation": "previews/full-charge-orbit.gif",
    "fullChargePoster": "previews/full-charge-orbit-poster.png",
    "motionPreview": "motion-preview.html",
    "artworkScope": "Approved full-charge 3D double-orbit GIF, Light/Dark and scrollbar designs; retained time-source and icon artwork. Example values only; no live telemetry or native animation performance claim. GIF timing is fitted to a seamless design-preview loop; App motion remains continuous.",
    "svgSources": sources, "sourcePackages": packages, "previews": previews,
    "installerAssetContractUnchanged": True,
}
(DEST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
paths = [p for p in sorted(DEST.rglob("*")) if p.is_file() and p.name != "SHA256SUMS.txt"]
(DEST / "SHA256SUMS.txt").write_text("".join(f"{digest(p)}  {p.relative_to(DEST)}\n" for p in paths))
print(json.dumps({"packages": packages, "previews": len(previews),
                  "svgMasters": sum(v[1] for v in FAMILIES.values())}, indent=2))
