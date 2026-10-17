# Approved icon integration — 4.3.15

The installed build contains the final side-chat artwork from
`c4b84050d9cff0e58b6e4a7fb914dc3dae20c435`: five Modules, three sidebar and
five General settings icons, plus the five Power SVG originals used in the
flow diagram and its power lanes. The final B plug outline is shared by connected
and disconnected states. Charging uses green, plugged/full uses blue, battery
power stays neutral, and mixed supply retains blue/amber distinctions. Capacity
bands and the charging bolt are preserved. The view caches resolved artwork so
telemetry-only updates do not redraw an unchanged icon.

Frozen production source: `b6c5d8d54bcd6945e99059958f498fa8d8eb9cdc`. Existing module order/default controls,
History implementation and the 4.3.14 `Calculating…` fix are retained. A separate
History performance candidate is outside this frozen build.

Validation:

- All 18 SVG masters, the design previews/archives and four production renderer
  files match the final side-chat source. The four SVG archives match their masters.
- 54 native XCTest cases pass in the disposable macOS 26.6.1 ARM VM, including
  optical bounds, state/appearance, cache, capacity, contrast and runtime tests.
  Eight native Settings contracts and 12 topology contracts pass.
- 48 real composited production-window captures cover eight fixture cases, both
  appearances and Classic/Standard/Clear. Production geometry, retained content
  and icon visibility assertions pass. Six representative images were visually
  inspected across all six required power states and all three materials.
- Five package cases pass: previous 4.3.14 installation, disabled-helper upgrade,
  fresh 4.3.15, reinstall and disabled-helper reinstall. Exact payload, versions,
  signatures, helper health/v5 and removal checks pass; the build also verifies
  matching App payloads in the PKG and DMG.
- The VM passes immediate and delayed cleanup after 98.313 seconds.
  Its clone and task-owned transfer copies are removed; the independent History
  VM and other user VMs are preserved.
- Native system Installer completes the canonical `/Applications/Wattson.app`
  update. App/helper/daemon bytes, marketing/build/receipt 4.3.15, signatures,
  helper health/v5 and normal process stability match the approved package.
- Canonical cleanup passes after 95.039 seconds of system monotonic time;
  no installation process, temporary expansion, mount or extra App registration
  remains. Prior 4.3.14 evidence is unchanged.

The [verification record](verification.json) binds the retained evidence.
The local distribution is `dist/local-v4.3.15`; its `design` directory includes
version-labeled approved previews and editable SVG archives for a future release.
Native App captures remain internal verification evidence, following the user's
publication preference. This is a verified local candidate, not a public GitHub
release, a macOS 27 result or a physical-battery fixture measurement.
