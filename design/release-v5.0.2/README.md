# Wattson 5.0.2 release

This update makes the source of battery-time estimates visible beside the
runtime title and brings the clock into the existing gradient Power icon family.
The user approved the design and authorized publication and a Chinese release
email to Cody on 2026-10-27.

- System-provided time uses a steady theme-colored planet.
- Controller or observed-discharge fallback uses slow breathing.
- Calculating starts an inclined comet orbit immediately: a 2.8-second lap and
  one synchronized breath, followed by a shared 0.5-second pause.
- Unavailable readings use a soft red pulse.

The clock and source indicator follow the instrument palette, including
charging green, plugged-idle/mixed blue and on-battery neutral. The official
macOS time remains a prediction; this release clarifies its source rather than
claiming improved accuracy or guaranteed battery life. Existing IOPS priority,
controller fallback, settling policy and observed-discharge calculation remain.

## Local acceptance

Product implementation commit: `a7621f735b01308ae8299b946da83f2c13dcd2e5`.
The release also contains the versioned design gallery and publication tools;
its final frozen SHA and remote run identities are recorded in `publication/`.

[Native implementation and verification](../battery-time-indicator/README.md)
records 735 passing Swift tests, 652 Python tests (4 expected skips), 20,000
animation stress iterations, a six-state light/dark production-renderer matrix,
real AppKit interaction, and actual WindowServer animation frames. Owned test
preferences, application registrations, temporary directories and the disposable
GUI VM were cleaned. Runtime screenshots remain internal verification evidence;
public artwork uses explicitly labelled design previews.

The local universal PKG/DMG passed structural and checksum verification. Public
assets must come from the reviewed exact-source CI candidate, not a local rebuild.
Community distribution uses ad-hoc App/helper signatures, unsigned PKG/DMG and
no notarization. The PKG synchronizes App/helper/receipt; the app-only DMG does
not install the helper and is not the upgrade route for existing PKG installs.

## Publication status

Preparation is in progress. No 5.0.2 public release or email is asserted by this
source document. Candidate, public artifact, Homebrew, Pages and canonical
installation evidence will be retained alongside the final release record.

Candidate validation exposed two pre-existing test-harness problems. Finite
stdin could stall across Apple Python 3.9 communication retries; the test owner
now stages those finite fixture inputs in a managed temporary file. The full
Headless CI for that correction passed on `4372ded`.

History completion checks now observe the hosted presentation tree before
flushing and checking the original animation keys. The original one-second
deadline remains, with three explicit negative controls for infinite, long and
retained animations. The extracted paired probe supports this change, but does
not establish the underlying Core Animation cause or replace the complete
interaction suite and candidate gate. Failed trials, visibility limitations and
cleanup warnings remain in [the diagnostic record](diagnostics/).

The next hosted attempt passed completion checks but exposed a separate
wall-clock race in the interrupted-axis fixture. A controlled 0.2-second delay
reproduced its failure with zero position error: the observation was too late
for the existing mid-transition guard. The fixture now holds the actual layer
at animation time 0.1 seconds during observation and retargeting, then resumes
continuously before the original one-second completion check. Both normal and
delayed extracted cases pass without changing production code or tolerances.
The complete suite and hosted release gate remain required for this correction.
