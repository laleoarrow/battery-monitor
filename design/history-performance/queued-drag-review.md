# Queued drag and History icon review

GO for integration and the remaining native GUI, package and installation gates. This is a read-only source/artifact review; no GUI or test suite was run.

The reviewed range is `402991a57fcbfa715e053b636cc54aceeb0a0a83` → `e62796901dae2255d7645840c21e0ee9b6b8f8c3`. Integrated source `9fef74944447d4753d1edde82997dc41a479ccad` contains identical Core/MenuBar/Popover production files and the corresponding Settings contract test relative to `e62796901dae2255d7645840c21e0ee9b6b8f8c3`.

- `beginReordering` tests live left-button bit 1 before snapshot preparation and immediately before session state is assigned. Released `[0]`, right-only `[2]`, and release-during-preparation `[1,0]` / `[1,2]` return before any session, order, row alpha or insertion feedback is changed. The upstream pending mouse-down event is already cleared. `[1,1]` preserves the original mouse-down event at the native boundary.
- New injectable button state, boundary observer and inspection hooks are DEBUG only. The production change adds no timer, polling loop or asynchronous work. Contract checks stop at the native boundary and do not prove an actual drag session; the other dialogue owns the rapid physical-mouse retest.
- The artwork change extends only the History area fill from x21 to x22. Stroke, nodes and the other four icons are unchanged. Five SVG/master hashes, renderer/preview metadata hashes and ZIP SVG bytes were checked. Running the existing generator in memory with its output write removed reproduced the frozen Swift renderer byte for byte.

History production hashes remain unchanged:

- `Core/HistoryChart.swift`: `bbc8051506c7c42b3e6f1906affb6d945b130fdf800e9e6040fc9412ee5f765a`
- `Popover/HistoryLayer.swift`: `091a8fde18fcf52064b238480796124d8ff2884937d9583e4f7780f48ef9ae2f`

The new [release log](build/queued-drag-final-release.log.gz) records both native slices, universal verification, byte-identical PKG/DMG app payloads and successful artifact checksums. Root directly observed release session 20518 exit 0; this reviewer did not rerun or independently observe that terminal session. All current dist manifest entries were rehashed:

- PKG: `72c2e20dcf13e6d69c27e9aee83528241ab58c881b1e1609a28f87b479caf21a`
- DMG: `dea278efddbe90e431cc5087e6837cfb64ea99a54d6f3ef919d030ffff89ea95`

The owned release root `/Users/leoarrow/Project/mypackage/agents/电池功率/.build/local.noindex/release.NuglxN` is absent, with no mount or process referencing it at inspection. Distribution remains community ad-hoc and not notarized. The log retains a nonfatal SwiftPM unhandled `__pycache__` warning. No new package-matrix or host-install result is claimed, and the old 91f package is not the candidate described by this review.

Machine-readable details and full artifact hashes: [queued-drag-review.json](queued-drag-review.json).
