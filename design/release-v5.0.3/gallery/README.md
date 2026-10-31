# Wattson 5.0.3 · animated full-charge design card

Four publication assets are final:

- `full-charge-orbit.gif`: 600 × 360, 20 fps, 640 frames, 32 seconds,
  infinite seamless loop; 323,535 bytes.
- `full-charge-orbit-poster.png`: clear first-frame fallback for mail and
  reduced-motion presentation.
- `full-charge-orbit-light.png` / `full-charge-orbit-dark.png`: paired static
  design cards. The dark image is identical to the poster.

This is an approved-design rendering, **not a running-App screenshot**. It
preserves the native fixed-plane 3D geometry, front/back sphere occlusion,
opposite directions, closed ±6% angular-speed variation, circular perspective
cores, historical 0.52-second tapered ribbons and theme-derived color family.
The reused clock artwork comes from the approved `power-icons-vector/clock.svg`.

The native App uses 8-second and 10.6-second periods. To make a compact,
uninterrupted promotional GIF, the design preview uses 8 and 32/3 seconds:
four outer and three inner laps close exactly at 32 seconds. The inner period
is 0.62893% longer than the App's. There are no fades, pauses or visible phase
resets. Marketing copy makes no exact period claim; this small loop-fitting
difference is recorded in `motion-provenance.json`.

The first frame contains the complete headline and a legible full-charge
state, including one foreground star, so the promotion remains informative in
clients that show only the first GIF frame. The public HTML gallery should use
the poster when Reduce Motion is requested. Email should include descriptive
alt text and a normal gallery link for blocked images.

The card is intentionally dark for stable contrast inside both light and dark
email clients; a separate light static design is supplied. Blue is the current
full-charge example, not an independent fixed-color rule for the App.

Verification:

- Both projected orbits enter the sphere silhouette in front and behind.
- Frames at t=0 and t=32 are pixel-identical before GIF quantization.
- Encoded GIF is 600 × 360, exactly 32 seconds and 640 frames; its NETSCAPE
  extension requests infinite looping.
- Both static themes fit without clipping or horizontal overflow.
- `motion-review.png` samples the **encoded GIF** every four seconds. Visual
  inspection found round small cores, correct occlusion and continuous tails.
- No JavaScript errors; the isolated browser closed, its profile and all 640
  temporary frames were removed, and the owned scratch parent has no runs.

Reproduce with the shared lifecycle owner:

```bash
bash design/release-v5.0.3/gallery/render-motion.sh /path/to/existing/playwright
```

The renderer uses the existing Chrome installation, blocks network requests,
and runs in a unique project-local `.noindex` profile. FFmpeg creates one global
128-color palette with ordered dithering and optimized frame differences.
The final files remain for publication; temporary frames and palette do not.
No product code, installed App, public page or email is modified by this script.
