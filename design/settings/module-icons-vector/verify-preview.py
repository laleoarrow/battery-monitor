#!/usr/bin/env python3
"""Check fade direction in the unedited production-renderer artwork proof."""
from pathlib import Path
import json
from PIL import Image

ASSETS = Path(__file__).resolve().parent
image = Image.open(ASSETS / "vector-preview.png").convert("RGB")
assert image.size == (1400, 660), "Unexpected proof layout; do not use stale sample coordinates"
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
    "rimRightRGB": [peak(1, 20.9634, 6.825, c) for c in range(3)],
    "rimLowerRGB": [peak(1, 12, 22.35, c) for c in range(3)],
    "lanesUpperBlue": peak(2, 19.1, 5.7, 2),
    "lanesLowerBlue": peak(2, 19.1, 20, 2),
    "historyAreaUpperBlue": peak(3, 18, 12, 2),
    "historyAreaLowerBlue": peak(3, 18, 19.5, 2),
    "historyStrokeBlue": peak(3, 18, 10.56, 2),
    "clockTrailStartBlue": peak(4, 16.56664, 7.09784, 2),
    "clockTrailEndBlue": peak(4, 18.16576, 9.37016, 2),
    "clockHandBlue": peak(4, 16, 12.3, 2),
}
checks = {
    "flowFadesAtStart": values["flowStartBlue"] + 40 < values["flowSettledBlue"],
    "rimBlueSweepBuildsAlongUpperArc": values["rimLeftRGB"][2] - values["rimLeftRGB"][0] + 30
        < values["rimRightRGB"][2] - values["rimRightRGB"][0],
    "rimLowerContourRemainsSolidNeutral": min(values["rimLowerRGB"]) > 200
        and max(values["rimLowerRGB"]) - min(values["rimLowerRGB"]) < 3,
    "lanesFillFadesTowardBaseline": background[2] < values["lanesLowerBlue"] < values["lanesUpperBlue"],
    "historyAreaFadesDownward": background[2] < values["historyAreaLowerBlue"] < values["historyAreaUpperBlue"],
    "historyFillQuieterThanStroke": values["historyAreaUpperBlue"] < values["historyStrokeBlue"],
    "clockTrailBuildsTowardHand": background[2] < values["clockTrailStartBlue"] < values["clockTrailEndBlue"],
    "clockTrailQuieterThanHand": values["clockTrailEndBlue"] < values["clockHandBlue"],
}
result = {
    "source": "Offscreen production vector renderer; no screenshot pixels were edited.",
    "measurement": "Relative displayed RGB levels, not an estimate of linear alpha.",
    "checks": checks, "pixels": values, "passed": all(checks.values()),
}
(ASSETS / "gradient-render-checks.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
assert result["passed"], "Gradient direction or visual hierarchy changed"
