from pathlib import Path
import hashlib, json, math, re, xml.etree.ElementTree as ET

source = Path(__file__).resolve().parent
assets = source.parent
inputs = [("pro-b-connected.svg", "adapter.svg"), ("pro-b-disconnected.svg", "disconnected.svg")]
records = []
for filename, output in inputs:
    data = (source / filename).read_bytes()
    svg = ET.fromstring(data)
    assert svg.get("viewBox") == "0 0 24 24"
    group = next(e for e in svg if e.tag.endswith("}g"))
    assert group.get("transform") == "translate(-0.75 0.5) rotate(40 12 12)"
    angle = math.radians(40)

    def rotate(point):
        x, y = point[0] - 12, point[1] - 12
        return (11.25 + x * math.cos(angle) - y * math.sin(angle),
                12.5 + x * math.sin(angle) + y * math.cos(angle))

    paths = []
    for element in group:
        assert element.tag.endswith("}path")
        props = dict(element.attrib)
        tokens = re.findall(r"[A-Za-z]|[-+]?(?:[0-9]*\.)?[0-9]+(?:[eE][-+]?[0-9]+)?", element.get("d"))
        segments = []; i = 0; x = y = 0
        while i < len(tokens):
            op = tokens[i]; i += 1
            n = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "Z": 0}[op]
            values = list(map(float, tokens[i:i+n])); i += n
            if op == "H": values = [values[0], y]; op = "L"
            if op == "V": values = [x, values[0]]; op = "L"
            points = list(zip(values[::2], values[1::2]))
            if points: x, y = points[-1]
            segments.append((op, list(map(rotate, points))))
        paths.append((segments, props))
    points = [p for segments, _ in paths for _, ps in segments for p in ps]
    minx, maxx = min(p[0] for p in points), max(p[0] for p in points)
    miny, maxy = min(p[1] for p in points), max(p[1] for p in points)
    # Leave room for the round stroke caps within the existing optical bounds.
    scale = 19 / max(maxx - minx, maxy - miny)

    def fit(point):
        return (12 + (point[0] - (minx + maxx) / 2) * scale,
                12 + (point[1] - (miny + maxy) / 2) * scale)

    def pair(point):
        return " ".join(f"{value:.8g}" for value in fit(point))

    defs = []
    for gradient in (e for e in svg.iter() if e.tag.endswith("}linearGradient")):
        p1 = fit(rotate((float(gradient.get("x1")), float(gradient.get("y1")))))
        p2 = fit(rotate((float(gradient.get("x2")), float(gradient.get("y2")))))
        stops = "".join(f'<stop offset="{stop.get("offset")}" stop-color="{stop.get("stop-color")}" stop-opacity="{stop.get("stop-opacity")}"/>' for stop in gradient)
        defs.append(f'<linearGradient id="{gradient.get("id")}" gradientUnits="userSpaceOnUse" x1="{p1[0]:.8g}" y1="{p1[1]:.8g}" x2="{p2[0]:.8g}" y2="{p2[1]:.8g}">{stops}</linearGradient>')
    shapes = []
    for segments, props in paths:
        d = " ".join(op + (" " + " ".join(pair(p) for p in ps) if ps else "") for op, ps in segments)
        if props.get("fill", "none") != "none":
            assert props.get("data-decorative") == "true"
            shapes.append(f'<path d="{d}" fill="{props["fill"]}" data-decorative="true"/>')
        if props.get("stroke", "none") != "none":
            shapes.append(f'<path d="{d}" stroke="{props["stroke"]}" stroke-width="{float(props["stroke-width"]) * scale:.8g}"/>')
    title = "Wattson selected Pro B — " + ("Disconnected" if output == "disconnected.svg" else "Adapter")
    result = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" color="#C7C7CC" fill="none" stroke-linecap="round" stroke-linejoin="round">\n'
    result += f'<title>{title}</title>\n<defs>' + "".join(defs) + '</defs>\n' + "\n".join(shapes) + '\n</svg>\n'
    (assets / output).write_text(result)
    records.append({"source": filename, "sourceSHA256": hashlib.sha256(data).hexdigest(),
                    "output": output, "uniformScale": scale,
                    "rotatedControlBounds": [minx, miny, maxx, maxy],
                    "strokeWidthScaledUniformly": True, "gradientTransformBaked": True})
(source / "normalization.json").write_text(json.dumps(records, indent=2) + "\n")
print("Imported calibrated Pro B states with shared geometry, exterior cable and uniform fit.")
