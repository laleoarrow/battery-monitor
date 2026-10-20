# Wattson 5.0.1 artwork preparation

The public gallery source is [`../releases/v5.0.1`](../releases/v5.0.1/README.md).
Its planned Pages URL is
<https://laleoarrow.github.io/battery-monitor/design/v5.0.1/>.
The existing Pages exporter copies that version-matched directory after the
stable-release gates pass; this preparation does not publish it.

The gallery retains five approved native offscreen artwork proofs in Dark/Light
pairs, including the four required supply states and the full six-state Power
matrix. Images are copied unchanged from the latest approved vector folders.
They illustrate the included artwork; the new whitelist interface, performance
changes, live telemetry, window compositing and animation are not pictured.
Runtime validation screenshots remain internal.

Four new version-labeled ZIPs contain the exact editable SVG masters: the
original five Modules icons plus the approved Process Activity icon, three
sidebar icons, five General icons and five Power masters, for 19 total. The
gallery links each ZIP and records its source/copy SHA-256 provenance. These
artwork downloads are separate from the four checksum-gated installer assets.
Earlier galleries and published assets are unchanged.

Local verification recorded in [`artwork-verification.json`](artwork-verification.json)
passed repeated byte-identical generation, XML/vector checks, ZIP integrity,
all 36 gallery checksums, local HTML link resolution, PNG dimensions and alt
text. All five images were visually inspected. Preparation creates final files
only, with no temporary files, app launches, registrations, preferences or mounts.

Public HTTPS links must still be checked without repository authentication after
Pages deployment and before announcing the release or sending a release email.
