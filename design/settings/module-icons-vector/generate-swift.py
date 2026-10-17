#!/usr/bin/env python3
"""Compile these five SVG masters into static AppKit paths; no runtime SVG parser."""
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


lines = [
    "// Generated from design/settings/module-icons-vector/*.svg. Edit the SVG masters.",
    "// Regenerate with: python3 design/settings/module-icons-vector/generate-swift.py",
    "import AppKit", "", "enum ModuleIconArtwork {",
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
for name in ("flow", "ring", "lanes", "history", "runtime"):
    svg = ET.parse(ASSETS / f"{name}.svg").getroot()
    if svg.attrib.get("viewBox") != "0 0 24 24":
        raise ValueError("Expected the common 24-unit artboard")
    lines.append(f"            case .{name}:")
    for element in svg:
        if element.tag.endswith("}title"):
            continue
        lines.append("                do {")
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
lines.extend(["            }", "            return true", "        }", "        image.isTemplate = false", "        return image", "    }", "}", ""])
OUTPUT.write_text("\n".join(lines))
print(OUTPUT)
