# Wattson 4.3.22 local preview

Built from frozen `7ec101a5b34a72539305d155608823aa42dc0b15`, including App-colored
activity bars and matching endpoint-colored glass action capsules/hover glow.
The release pipeline verified arm64/x86_64, strict signatures, packaging,
checksums and byte-identical PKG/DMG App contents. The canonical PKG update is
currently awaiting native macOS administrator authorization. No installation
success or canonical popup interaction is claimed until verified.

The pre-install baseline hashes all 15 existing App settings; no raw preference
values are retained in the evidence. The intended upgrade preserves enabled
Process Activity, Top 3 and Compact view. No user process is terminated.

[Package metadata](verified-package.json) and [source commit](source-commit.txt)
identify the final candidate. Earlier uninstalled bar-only package evidence is
retained under `bar-only-package/`; its distribution files were moved to
`dist/local-preview-v4.3.22-bar-only/` before rebuilding the same unpublished
version with capsule colors. The final artifacts are in
`dist/local-preview-v4.3.22/`. Neither candidate was published to GitHub.
App/helper are ad-hoc signed; the PKG is unsigned and not notarized.
