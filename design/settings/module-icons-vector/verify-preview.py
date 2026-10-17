#!/usr/bin/env python3
"""Check fade direction in the unedited production-renderer artwork proof."""
from pathlib import Path
import json
import math
import re
import xml.etree.ElementTree as ET
from PIL import Image

ASSETS = Path(__file__).resolve().parent
image = Image.open(ASSETS / "vector-preview.png").convert("RGB")
assert image.size == (1680, 660), "Unexpected proof layout; do not use stale sample coordinates"
background = image.getpixel((0, 0))


def peak(module, x, y, channel):
    # Enlarged 120px icons use the SVG's 24-unit coordinates, in the dark row.
    px = round(80 + 280 * module + 5 * x)
    py = round(73 + 5 * y)
    return max(image.getpixel((px + dx, py + dy))[channel]
               for dx in range(-1, 2) for dy in range(-1, 2))


values = {
    "backgroundRGB": background,
    "flowStartBlue": peak(0, 2.2, 4.5, 2),
    "flowSettledBlue": peak(0, 2.2, 6.9, 2),
    "rimLeftRGB": [peak(1, 3.0366, 6.825, c) for c in range(3)],
    "rimRightRGB": [peak(1, 19.31856, 4.68144, c) for c in range(3)],
    "rimLowerRGB": [peak(1, 12, 22.35, c) for c in range(3)],
    "lanesUpperBlue": peak(2, 19.1, 5.7, 2),
    "lanesLowerBlue": peak(2, 19.1, 20, 2),
    "historyAreaUpperBlue": peak(3, 18, 12, 2),
    "historyAreaLowerBlue": peak(3, 18, 19.5, 2),
    "historyStrokeBlue": peak(3, 18, 10.56, 2),
    "clockSectorFaintBlue": peak(4, 13.6, 8.2, 2),
    "clockSectorStrongBlue": peak(4, 16, 10.8, 2),
    "clockSectorOutsideBlue": peak(4, 18, 6, 2),
    "clockHandBlue": peak(4, 16, 12.3, 2),
}
ring = ET.parse(ASSETS / "ring.svg").getroot()
sweep = next(e for e in ring if e.get("stroke") == "url(#powerArc)")
coordinates = [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", sweep.get("d"))]
end_x, end_y = coordinates[-2:]
endpoint_angle = math.degrees(math.atan2(end_y - 12, end_x - 12))
pointer_angle = math.degrees(math.atan2(6.85 - 12, 17.15 - 12))
values["rimEndpointAngleDegrees"] = endpoint_angle
values["pointerAngleDegrees"] = pointer_angle
checks = {
    "flowFadesAtStart": values["flowStartBlue"] + 40 < values["flowSettledBlue"],
    "rimBlueSweepBuildsAlongUpperArc": values["rimLeftRGB"][2] - values["rimLeftRGB"][0] + 30
        < values["rimRightRGB"][2] - values["rimRightRGB"][0],
    "rimLowerContourRemainsSolidNeutral": min(values["rimLowerRGB"]) > 200
        and max(values["rimLowerRGB"]) - min(values["rimLowerRGB"]) < 3,
    "rimEndAlignedWithPointer": abs(endpoint_angle - pointer_angle) < 0.001,
    "lanesFillFadesTowardBaseline": background[2] < values["lanesLowerBlue"] < values["lanesUpperBlue"],
    "historyAreaFadesDownward": background[2] < values["historyAreaLowerBlue"] < values["historyAreaUpperBlue"],
    "historyFillQuieterThanStroke": values["historyAreaUpperBlue"] < values["historyStrokeBlue"],
    "clockSectorFadesTowardHand": background[2] < values["clockSectorFaintBlue"]
        < values["clockSectorStrongBlue"] < values["clockHandBlue"],
    "clockSectorStaysInsideRegion": values["clockSectorOutsideBlue"] == background[2],
}
result = {
    "source": "Offscreen production vector renderer; no screenshot pixels were edited.",
    "measurement": "Relative displayed RGB levels, not an estimate of linear alpha.",
    "checks": checks, "pixels": values, "passed": all(checks.values()),
}
(ASSETS / "gradient-render-checks.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
assert result["passed"], "Gradient direction or visual hierarchy changed"
