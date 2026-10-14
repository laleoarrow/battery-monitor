# Wattson 4.3.2 local trial — 2026-10-14

The user approved the final runtime section and requested a native PKG update
of the canonical local installation. This is a local trial, not a published
GitHub release or a completed public release matrix.

## Artifact and installation

- Frozen build source: `ff2274a7becef9c4600d415396db1d46c51a444c`.
- PKG: `dist/Wattson-v4.3.2-macos-universal.pkg`.
- PKG SHA-256: `7575f98e25dc059d9fc613f0d6a2652603cd2a94d264eb4fd2bb6f71588a5291`.
- App-only DMG and signing metadata are retained beside the PKG.
- Versioned checksum manifests preserve both 4.3.1 and 4.3.2 artifact hashes.
- Universal arm64/x86_64 app and helper; deployment target macOS 12.
- Community ad-hoc signatures; unsigned PKG/DMG; not notarized.

The native Installer reported success. Installed app marketing/build versions
and `com.leoarrow.wattson.pkg` receipt all equal `4.3.2`. All 13 app files, the
helper and LaunchDaemon plist match the verified build byte for byte. App/helper
strict signature checks passed, and production entitlements match the repository
without `get-task-allow`. The PKG and DMG contain identical app bytes.

The canonical `/Applications/Wattson.app` was relaunched and remained running.
Helper health, v5 observation and live power probes passed. Existing sandbox
preferences matched the pre-install snapshot. Spotlight and the local
LaunchServices inventory identify only the canonical app; historical Time
Machine registrations were not modified.

## Validation and footer clarification

- Swift tests with warnings treated as errors: 383 passed, zero failures.
- Python suite: 503 tests, zero failures, four intentional skips.
- Shell syntax and whitespace checks passed.
- Release artifact structure and SHA-256 verification passed.
- Real AppKit interaction in the disposable ARM VM: 300/300 normal assertions
  and 294/294 Reduce Motion assertions passed. One in-flight close-animation
  phase is inapplicable under Reduce Motion's synchronous close.
- Entrance-animation stress: 20,000 iterations passed.

The first VM run used an actual 1024×768 display. Each interaction mode had
three runtime visibility height assertions fail because the popup viewport was
screen-capped: the footer moved the expected 88 points while the window shrank
only 57. With only the VM session display changed to 1600×1200, the same source
and assertions passed completely. Both first-run logs and successful rerun logs
are retained. The original display was restored, test apps and temporary guest
files cleaned, and TestLab stopped; Base remained stopped throughout.

The user's screenshot compares their normal Glass footer with a Classic preview
captured under Reduce Motion and Reduce Transparency. `PopoverFooterView` and
the four selector implementations are byte-identical to the `v4.3.1` tag.
The gray native segmented fallback does not replace the normal
interactive Glass capsule. No power-mode behavior was changed for this layout.
The VM checks passed for selection, keyboard input, drag intent, disabled/busy
states, confirmation and failure rollback. These use the real AppKit controls
with test callbacks; they do not change the host Mac's actual power mode.

The final runtime layout has twelve production-render cases and 315 passing
geometry assertions, with both title and time right-aligned below History.
These are fixture-based Classic content renders, not native Glass composites.
The local menu-bar accessory app's UI automation read timed out, so no new live
composited screenshot is claimed. VM capture permission limitations remain
documented in the linked layout review.

Detailed build/test logs, payload hashes, before/after installation records and
VM results are retained in `.build/local-4.3.2-review.noindex/`. Preference
snapshots remain local in that ignored directory and are not committed.
