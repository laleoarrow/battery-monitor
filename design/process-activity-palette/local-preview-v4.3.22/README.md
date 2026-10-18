# Wattson 4.3.22 local preview

Built from frozen `7ec101a5b34a72539305d155608823aa42dc0b15`, including App-colored
activity bars and matching endpoint-colored glass action capsules/hover glow.
The release pipeline verified arm64/x86_64, strict signatures, packaging,
checksums and byte-identical PKG/DMG App contents. The native macOS Installer
completed the canonical PKG upgrade after the user authorized it; its success
page was directly observed and captured.

Installed marketing/build/receipt versions are 4.3.22. Payload comparisons show
the App, helper and daemon exactly match the verified package. Strict signatures,
both architectures, helper health/V5 and native process sampling all pass. All
15 existing App settings match the fresh pre-install hashes, retaining enabled
Process Activity, Top 3 and Compact view. No raw preference values or process
identities are retained in the evidence, and no user process was terminated.

See the [installation record](local-install-verified.json) and
[verification log](install-verification.log). The canonical App was launched
with the normal background-launch path. Its stable PID checks process lifetime;
canonical popup opening and closing were not directly observed after this
upgrade. The source passed 68 focused tests and the six-state production-renderer
matrix of 172 captures / 15,532 assertions. Build, test and expanded-payload
scratch directories and their temporary App registrations are cleaned.

[Package metadata](verified-package.json) and [source commit](source-commit.txt)
identify the final candidate. Earlier uninstalled bar-only package evidence is
retained under `bar-only-package/`; its distribution files were moved to
`dist/local-preview-v4.3.22-bar-only/` before rebuilding the same unpublished
version with capsule colors. The final artifacts are in
`dist/local-preview-v4.3.22/`. Neither candidate was published to GitHub.
App/helper are ad-hoc signed; the PKG is unsigned and not notarized.
