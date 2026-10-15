# Native Settings hierarchy

This source revision reorganizes Wattson Settings using the existing AppKit
controls and native window/sidebar hosts. It is not a release or an update to
the installed `/Applications/Wattson.app`.

## Decisions

General has four named groups in a predictable top-to-bottom order:

1. **Startup & Menu Bar** — launch at login and the system battery icon.
2. **Updates** — manual and launch-time update checks.
3. **Appearance** — theme, glass, in-app logo and Dock icon.
4. **Support** — the existing feedback report action.

Every group uses the same external 13-point semibold title, an 8-point
title-to-content gap and a 16-point inter-group gap. Updates remain distinct
from feedback, which creates a clear place to seek help. The retained General
scroll view provides access to all groups and their expanded recovery content.

General and Modules share regular 20-point SF Symbols in 28-point alignment
frames. General's decorative bordered icon tiles are removed. Startup uses
`power`, the menu-bar setting and Display navigation use `menubar.rectangle`,
manual updates use `arrow.down.circle` and launch-time checks use
`arrow.clockwise`. Existing module and feedback symbols are retained with the
same size/weight. Symbols supplement accessible text rather than becoming
additional VoiceOver stops.

Theme, Liquid Glass, In-App Logo and Dock Icon are peer rows at the same
16-point label inset. Only Popup background and Transparency have a 32-point
inset because they depend on Liquid Glass. Fine separators distinguish peers;
the glass dependencies remain within their parent's surface. Logo and Dock
use the same primary label typography as Theme. The Dock explanation retains
space for both lines. The optional recovery action follows the startup
controls in both the visual order and keyboard loop, including after refresh
and theme changes.

Display and Modules each have one main list. Their page title and introductory
text already identify that list, so they do not gain a redundant group title.
The native toolbar title in Glass and inline heading in Classic are preserved.

## Design references and Pro review

The current official Apple guidance was consulted on 2026-10-15:

- [Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
  — related settings belong together and navigation should stay familiar.
- [Boxes](https://developer.apple.com/design/human-interface-guidelines/boxes)
  — use alignment and padding for subgroups and avoid nested visual enclosures.
- [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
  — consistent symbol weight/scale, meaningful imagery and OS availability.

The user's SunBrowser ChatGPT **Pro** selector was verified before requesting
an architecture review. The [Pro design review](https://chatgpt.com/c/6ad05ec4-72b8-83ec-8be1-bcc63c247292)
recommended named groups, bare SF Symbols, aligned Appearance peers and
indentation only for true glass dependencies. Those principles were adopted.
Four groups preserve a separate Support destination; existing row heights and
native page-title behavior are retained. Point sizes and spacing are Wattson
implementation choices, not dimensions prescribed by Apple.

Pro then received three inspected compositor images (General, Appearance and
Modules in Light Glass) for a separate screenshot-only review. Its final
response was “通过。” No further visual correction was requested.

## Evidence

- [Before](before/README.md): six Classic production-view layout renders.
- [After](after/README.md): actual own-window compositor captures in the
  disposable ARM GUI VM, with source hashes, power fixtures, themes and
  accessibility cases described in the manifest.

The tests exercise the retained production Settings hierarchy, label/symbol
alignment, peer/dependent label columns, keyboard order, recovery refresh,
theme retention and optical margins. Capture fixtures use in-memory
preferences and mocked privileged operations; their battery values are fixed
samples. The review does not imply a manual VoiceOver audit or a new release.

Headless validation on the final source:

- `swift test`: 418 tests passed.
- `python3 -m unittest discover -s tests -v`: 546 tests, successful with four
  optional interaction/stress cases skipped on the active desktop.
- Focused Settings contracts: eight Python tests and six Swift tests passed.
- Disposable-VM GUI Settings contract: eight tests passed, including 500
  reuse and 500 creation/release cycles, with file descriptors stable at four.
- Shell syntax checks and `git diff --check` passed.

See [after/README.md](after/README.md) for the separate disposable-VM GUI run
and the exact capture matrix. The installed app/helper/receipt remain 4.3.3;
distribution artifacts and release tags are outside this source refinement.
