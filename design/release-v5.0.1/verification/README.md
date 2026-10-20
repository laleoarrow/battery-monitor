# Local release preparation

- Version: 5.0.1, combining whitelist source 9276560 with the retained performance
  commits 7169eca / 5d5391a already in its history.
- Swift: 728 tests passed, zero failures (`swift-tests.log`).
- Local universal PKG/DMG: built and checked successfully (`local-release.log`).
  Both packages contain byte-identical apps. They use the documented community
  signing policy. Build scratch, mounts and app registrations were cleaned.
  These local build bytes are not the final GitHub candidate bytes.
- Version-configured website: seven rendered/export tests and lint passed
  (`website-test.log`, `website-lint.log`). Generated website copies were checked
  against their source and removed; tracked export files were restored.
- Artifact preparation: 30 offline acceptance/rejection checks passed.
- Installation preparation: six read-only validation checks passed.
- Versioned artwork: 36 checksum entries, 19 SVG masters and four deterministic
  ZIPs verified; all five approved offscreen preview images inspected.

Exact frozen-main hosted CI, candidate install matrix, public downloads,
Homebrew, Pages and the canonical installation are separate required gates.
Their actual results belong in publication/ and installation/.
