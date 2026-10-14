# Wattson 4.3.2

Battery Time Estimate is an independently selectable section below Power History, with the same separators and neutral colors as the other instruments. Its right-aligned title switches between **Estimated Battery Runtime** on battery power and **Estimated Time to Full** on external power. Charging shows macOS's time-to-full estimate; a full battery shows **Fully Charged**, and mixed supply shows **Not Charging**. This release also fixes repeated menu-bar clicks and glass clipping, and adds diagnostic feedback through a reviewable GitHub issue draft.

## Earlier installed trial: replacement capture pending

The image below is a composited screen-region capture of the earlier installed local 4.3.2 trial, taken on 2026-10-14 from [`ff2274a`](https://github.com/laleoarrow/battery-monitor/commit/ff2274a7becef9c4600d415396db1d46c51a444c). It preserves the native Standard Glass controls, but its **External Power** runtime status predates the dynamic battery-time behavior shown in the new fixtures below. This older trial image is pending replacement before publication and is not evidence of the current charging/full labels.

<a href="installed-standard-dark-screen.png"><img src="installed-standard-dark-screen.png" alt="Earlier local Wattson 4.3.2 trial in Standard Glass, Dark appearance; old External Power status pending replacement" width="360"></a>

## Power-state layout previews: Classic

The following twelve images were captured on 2026-10-15 with the production AppKit renderer in hidden windows, using **Classic**, **Reduce Transparency**, and **Reduce Motion**. They are deterministic layout fixtures, not composited Liquid Glass captures or live readings. The charging estimate `42m`, remaining-runtime estimates `4h 25m`, `18m`, and `5h 10m`, power readings, battery details, and history are fixed samples.

The footer uses the capture process's cached/default power mode. The Low Power fixture changes the displayed snapshot only and does not simulate a hardware power-mode switch. Click any image to view it at full resolution.

<table>
<tr><th>Light</th><th>Dark</th></tr>
<tr><td colspan="2"><strong>On battery</strong></td></tr>
<tr><td><a href="runtime-section-light-battery.png"><img src="runtime-section-light-battery.png" alt="Classic fixed-sample layout: On battery, light" width="360"></a></td><td><a href="runtime-section-dark-battery.png"><img src="runtime-section-dark-battery.png" alt="Classic fixed-sample layout: On battery, dark" width="360"></a></td></tr>
<tr><td colspan="2"><strong>Charging</strong></td></tr>
<tr><td><a href="runtime-section-light-charging.png"><img src="runtime-section-light-charging.png" alt="Classic fixed-sample layout: Charging, light" width="360"></a></td><td><a href="runtime-section-dark-charging.png"><img src="runtime-section-dark-charging.png" alt="Classic fixed-sample layout: Charging, dark" width="360"></a></td></tr>
<tr><td colspan="2"><strong>Full</strong></td></tr>
<tr><td><a href="runtime-section-light-full.png"><img src="runtime-section-light-full.png" alt="Classic fixed-sample layout: Full, light" width="360"></a></td><td><a href="runtime-section-dark-full.png"><img src="runtime-section-dark-full.png" alt="Classic fixed-sample layout: Full, dark" width="360"></a></td></tr>
<tr><td colspan="2"><strong>Mixed supply</strong></td></tr>
<tr><td><a href="runtime-section-light-mixed.png"><img src="runtime-section-light-mixed.png" alt="Classic fixed-sample layout: Mixed supply, light" width="360"></a></td><td><a href="runtime-section-dark-mixed.png"><img src="runtime-section-dark-mixed.png" alt="Classic fixed-sample layout: Mixed supply, dark" width="360"></a></td></tr>
<tr><td colspan="2"><strong>Low battery</strong></td></tr>
<tr><td><a href="runtime-section-light-low-battery.png"><img src="runtime-section-light-low-battery.png" alt="Classic fixed-sample layout: Low battery, light" width="360"></a></td><td><a href="runtime-section-dark-low-battery.png"><img src="runtime-section-dark-low-battery.png" alt="Classic fixed-sample layout: Low battery, dark" width="360"></a></td></tr>
<tr><td colspan="2"><strong>Low Power</strong></td></tr>
<tr><td><a href="runtime-section-light-low-power.png"><img src="runtime-section-light-low-power.png" alt="Classic fixed-sample layout: Low Power, light" width="360"></a></td><td><a href="runtime-section-dark-low-power.png"><img src="runtime-section-dark-low-power.png" alt="Classic fixed-sample layout: Low Power, dark" width="360"></a></td></tr>
</table>

The [capture harness](../../../tests/visual/capture_runtime_sections.swift) passed 315 assertions across these twelve cases, including battery-time direction and state text, numeric/status typography, placement, text fitting, separators, visibility changes, and absence of a residual gap. The installed app, helper, preferences, and foreground application were unchanged during these fixture captures. This is local layout validation; hosted release and installation gates are verified separately.

[Checksums for all 13 images](SHA256SUMS.txt).
