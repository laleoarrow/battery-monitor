#!/usr/bin/env python3
"""Compile module and sidebar SVG masters into static AppKit paths."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
ASSETS = Path(__file__).resolve().parent
OUTPUT = ROOT / "MenuBar/ModuleIconArtwork.swift"


def number(value):
    return format(float(value), ".8g")


def point(x, y):
    return f"NSPoint(x: {number(x)}, y: {number(y)})"


def commands(element):
    kind = element.tag.rsplit("}", 1)[-1]
    a = element.attrib
    if kind == "circle":
        x, y, r = (float(a[k]) for k in ("cx", "cy", "r"))
        return [f"let path = NSBezierPath(ovalIn: NSRect(x: {number(x-r)}, y: {number(y-r)}, width: {number(2*r)}, height: {number(2*r)}))"]
    if kind == "rect":
        values = ", ".join(f"{k}: {number(a[k])}" for k in ("x", "y", "width", "height"))
        radius = number(a.get("rx", 0))
        return [f"let path = NSBezierPath(roundedRect: NSRect({values}), xRadius: {radius}, yRadius: {radius})"]
    result = ["let path = NSBezierPath()"]
    if kind == "polyline":
        values = re.findall(r"-?\d+(?:\.\d+)?", a["points"])
        for i in range(0, len(values), 2):
            method = "move(to:" if i == 0 else "line(to:"
            result.append(f"path.{method} {point(*values[i:i+2])})")
        return result
    if kind != "path":
        raise ValueError(f"Unsupported SVG object: {kind}")
    tokens = re.findall(r"[MLCZ]|-?\d+(?:\.\d+)?", a["d"])
    i = 0
    while i < len(tokens):
        op = tokens[i]
        i += 1
        count = {"M": 2, "L": 2, "C": 6, "Z": 0}[op]
        values = tokens[i:i+count]
        i += count
        if op in ("M", "L"):
            method = "move(to:" if op == "M" else "line(to:"
            result.append(f"path.{method} {point(*values)})")
        elif op == "C":
            result.append(f"path.curve(to: {point(*values[4:6])}, controlPoint1: {point(*values[:2])}, controlPoint2: {point(*values[2:4])})")
        else:
            result.append("path.close()")
    return result


def color(value):
    return {"currentColor": "ink", "#0A84FF": "accent"}[value]


def gradient_commands(element, gradients, stroke):
    paint = element.get("stroke" if stroke else "fill")
    gradient = gradients[paint[5:-1]]
    kind = element.tag.rsplit("}", 1)[-1]
    if kind == "circle":
        a = element.attrib
        x, y, r = (float(a[k]) for k in ("cx", "cy", "r"))
        result = ["let path = CGMutablePath()",
                  f"path.addEllipse(in: CGRect(x: {number(x-r)}, y: {number(y-r)}, width: {number(2*r)}, height: {number(2*r)}))"]
    elif kind == "rect":
        a = element.attrib
        values = ", ".join(f"{k}: {number(a[k])}" for k in ("x", "y", "width", "height"))
        radius = number(a.get("rx", 0))
        result = ["let path = CGMutablePath()",
                  f"path.addRoundedRect(in: CGRect({values}), cornerWidth: {radius}, cornerHeight: {radius})"]
    else:
        result = [line.replace("NSBezierPath()", "CGMutablePath()")
                  .replace("path.line(to:", "path.addLine(to:")
                  .replace("path.curve(to:", "path.addCurve(to:")
                  .replace("controlPoint1:", "control1:").replace("controlPoint2:", "control2:")
                  .replace("path.close()", "path.closeSubpath()") for line in commands(element)]
    colors, locations = [], []
    solid_contrast = stroke or element.get("data-contrast") == "solid"
    for stop in gradient:
        alpha = number(stop.get("stop-opacity", 1))
        opacity = f"(increasedContrast ? 1 : {alpha})" if solid_contrast else alpha
        colors.append(f"{color(stop.get('stop-color'))}.withAlphaComponent({opacity}).cgColor")
        locations.append(number(stop.get("offset")))
    width = f"{number(element.get('stroke-width', 1))} * contrastScale" if stroke else "nil"
    start = point(gradient.get("x1"), gradient.get("y1"))
    end = point(gradient.get("x2"), gradient.get("y2"))
    result.extend([f"drawGradient(path, strokeWidth: {width},",
                   f"             colors: [{', '.join(colors)}],",
                   f"             locations: [{', '.join(locations)}], start: {start}, end: {end})"])
    if not stroke and element.get("stroke", "none") != "none":
        result.append(f"stroke(path, color: {color(element.get('stroke'))}, width: {number(element.get('stroke-width', 1))} * contrastScale)")
    return result


def emit_cases(lines, assets, names):
    for name in names:
        svg = ET.parse(assets / f"{name}.svg").getroot()
        if svg.attrib.get("viewBox") != "0 0 24 24":
            raise ValueError("Expected the common 24-unit artboard")
        gradients = {e.get("id"): e for e in svg.iter() if e.tag.endswith("}linearGradient")}
        lines.append(f"            case .{name}:")
        for element in svg:
            if element.tag.endswith(("}title", "}defs")):
                continue
            lines.append("                do {")
            gradient_stroke = element.get("stroke", "").startswith("url(#")
            gradient_fill = element.get("fill", "").startswith("url(#")
            if gradient_stroke or gradient_fill:
                decorative = element.get("data-decorative") == "true"
                if decorative:
                    lines.append("                    if !increasedContrast {")
                indent = "                        " if decorative else "                    "
                lines.extend(indent + command for command in gradient_commands(element, gradients, stroke=gradient_stroke))
                if decorative:
                    lines.append("                    }")
                lines.append("                }")
                continue
            lines.extend("                    " + command for command in commands(element))
            if element.get("fill", "none") != "none":
                lines.extend([f"                    {color(element.get('fill'))}.setFill()", "                    path.fill()"])
            if element.get("stroke", "none") != "none":
                lines.extend([
                    f"                    {color(element.get('stroke'))}.setStroke()",
                    f"                    path.lineWidth = {number(element.get('stroke-width', 1))} * contrastScale",
                    "                    path.lineCapStyle = .round",
                    "                    path.lineJoinStyle = .round",
                    "                    path.stroke()",
                ])
            lines.append("                }")


lines = [
    "// Generated from design/settings/{module,sidebar}-icons-vector/*.svg. Edit the SVG masters.",
    "// Regenerate with: python3 design/settings/module-icons-vector/generate-swift.py",
    "import AppKit", "", "enum ModuleIconArtwork {",
    "    enum SidebarIcon: CaseIterable { case general, display, modules }", "",
    "    static func image(for module: Settings.Module, side: CGFloat, ink: NSColor,",
    "                      accent: NSColor, increasedContrast: Bool) -> NSImage {",
    "        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in",
    "            NSGraphicsContext.saveGraphicsState()",
    "            defer { NSGraphicsContext.restoreGraphicsState() }",
    "            let transform = NSAffineTransform()",
    "            transform.translateX(by: rect.minX, yBy: rect.maxY)",
    "            transform.scaleX(by: rect.width / 24, yBy: -rect.height / 24)",
    "            transform.concat()",
    "            let contrastScale: CGFloat = increasedContrast ? 1.2 : 1",
    "            switch module {",
]
emit_cases(lines, ASSETS, ("flow", "ring", "lanes", "history", "runtime"))
lines.extend(["            }", "            return true", "        }", "        image.isTemplate = false", "        return image", "    }", ""])
lines.extend([
    "    static func sidebarImage(for icon: SidebarIcon, side: CGFloat, ink: NSColor,",
    "                             accent: NSColor, increasedContrast: Bool) -> NSImage {",
    "        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in",
    "            NSGraphicsContext.saveGraphicsState()",
    "            defer { NSGraphicsContext.restoreGraphicsState() }",
    "            let transform = NSAffineTransform()",
    "            transform.translateX(by: rect.minX, yBy: rect.maxY)",
    "            transform.scaleX(by: rect.width / 24, yBy: -rect.height / 24)",
    "            transform.concat()",
    "            let contrastScale: CGFloat = increasedContrast ? 1.2 : 1",
    "            switch icon {",
])
emit_cases(lines, ASSETS.parent / "sidebar-icons-vector", ("general", "display", "modules"))
lines.extend(["            }", "            return true", "        }", "        image.isTemplate = false", "        return image", "    }", ""])
lines.extend('''    private static func drawGradient(_ path: CGPath, strokeWidth: CGFloat?,
                                     colors: [CGColor], locations: [CGFloat],
                                     start: CGPoint, end: CGPoint) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray,
                                        locations: locations) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        if let strokeWidth {
            context.setLineWidth(strokeWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
        }
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func stroke(_ path: CGPath, color: NSColor, width: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }
}
'''.splitlines())
OUTPUT.write_text("\n".join(lines) + "\n")
print(OUTPUT)
