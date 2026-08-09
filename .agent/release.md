# Wattson release and deployment

## Community release

The normal public build intentionally matches iData's community distribution
model and does not require Developer ID credentials:

```bash
bash scripts/release.sh "$(tr -d '\r\n' < VERSION)"
```

The command builds and verifies:

- `Wattson-v<version>-macos-universal.pkg`
- `Wattson-v<version>-macos-universal.dmg`
- `Wattson-v<version>-release-info.txt`
- `SHA256SUMS.txt`

The DMG contains exactly one visible item: the byte-identical native PKG. The
PKG is the canonical installation surface for DMG, direct download, and the
Homebrew cask.

## Optional Developer ID path

Set both `WATTSON_DEVELOPER_ID_APP` and
`WATTSON_DEVELOPER_ID_INSTALLER`. Set `WATTSON_NOTARIZE=1` only with a valid
notary keychain profile or API-key variables. Never describe an artifact as
notarized unless `notarytool` returned `Accepted` and `stapler validate` passed.

## Required release gate

1. Headless SwiftPM and Python suites pass.
2. Real AppKit interaction and animation stress pass in an available GUI
   session.
3. Release artifacts build locally and their checksums verify.
4. One uploaded artifact set passes fresh-runner install, helper health,
   disabled-service reinstall, upgrade, app-process launch stability, and
   uninstall cleanup on the declared Intel/Apple-silicon macOS matrix. The real
   menu-bar readiness path remains covered by the AppKit interaction suite on a
   battery-equipped Mac because hosted Mac mini runners have no internal battery.
5. GitHub headless CI and the release-candidate matrix are green.
6. Create the annotated tag and stable GitHub release from that exact commit
   and exact candidate artifact bytes.
7. Require the promotion-dispatched Homebrew synchronization and tag-pinned
   Pages deployment to finish green before announcing the release. Promotion
   dispatches these explicitly because a release created with `GITHUB_TOKEN`
   does not emit another workflow run from a normal `release` trigger.

If `HOMEBREW_TAP_TOKEN` is unavailable, the release workflow still downloads
and verifies every stable asset and generates the exact cask without pushing.
Sync that cask from a trusted maintainer checkout and require the separate
`laleoarrow/homebrew-tap` CI run to pass before announcement.

The website reads GitHub's stable `releases/latest`; publish v3 before deploying
the site so it cannot advertise an older architecture-limited release.

## Local developer install

```bash
bash scripts/install.sh
```

This retains the user-local development path and is not the public v3 package.
Use `scripts/uninstall.sh` for complete v2/v3 cleanup. Never replace or launch
the user's installed app merely to perform a headless build check.
