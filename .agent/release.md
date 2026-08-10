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
7. Promotion explicitly dispatches Homebrew validation/synchronization because
   a release created with `GITHUB_TOKEN` does not emit another workflow run
   from a normal `release` trigger. The Homebrew workflow must observe the exact
   release version and PKG checksum in the public cask before dispatching the
   Intel and Apple-silicon public lifecycle tests, and the exact tap commit must
   first pass its own `brew test-bot` workflow. Promotion publishes the stable
   release without changing `releases/latest`; only after both public lifecycle
   jobs pass is it marked latest and the stable-release Pages workflow
   dispatched. Pages builds the current tested `main` commit only when its
   `VERSION` still matches that stable release tag.
   GitHub Pages must already use **GitHub Actions** as its publishing source.
   Announce the release only after Pages is green.

For an unattended release, first push the final commit to `main`, freeze it,
then push the identical SHA to `release-candidate`. A successful candidate run
automatically starts promotion. Promotion rejects any candidate whose workflow,
origin branch, completion state, or head SHA does not match the approved release
contract, and also requires successful Headless CI for that same `main` SHA.
The manual candidate and promotion dispatches remain the fallback.

If `HOMEBREW_TAP_TOKEN` is unavailable, the release workflow still downloads
and verifies every stable asset and generates the exact cask, but then fails
closed without pushing or dispatching later stages. Sync that cask from a
trusted maintainer checkout and require the separate `laleoarrow/homebrew-tap`
CI run to pass before continuing.

After a trusted manual tap sync, push the current `main` commit to the recovery
branch `homebrew-ready/v<version>`. That branch is only a signal to resume the
public validation chain: the workflow derives the release tag from the branch,
requires the recovery commit to equal the current remote `main` SHA and requires
a successful Headless CI `push` run for that same SHA. It then downloads the
stable PKG, DMG, release metadata, and checksum manifest, verifies all checksums,
requires the public cask to contain that exact version and PKG SHA, and requires
the exact public tap commit's `tests.yml` push run to have completed successfully
before starting either hosted-macOS lifecycle job. The recovery tag must match
the `VERSION` file at current `main`; each runner disables Homebrew auto-update
and requires its tapped repository to remain at that exact tested commit.

A manual `workflow_dispatch` from `main` with an explicit release tag remains
the audited fallback and passes through the same fail-closed checks. Neither
entry path may mark the release latest or dispatch Pages until both the Intel
and Apple-silicon public install/helper/uninstall lifecycles succeed.

The Pages workflow requires successful Headless CI for the exact current
`main` commit and requires its `VERSION` to match the supplied stable release
tag. Keep that release marked latest before deploying so the website and public
downloads stay aligned.

## Local developer install

```bash
bash scripts/install.sh
```

This retains the user-local development path and is not the public v3 package.
Use `scripts/uninstall.sh` for complete v2/v3 cleanup. Never replace or launch
the user's installed app merely to perform a headless build check.
