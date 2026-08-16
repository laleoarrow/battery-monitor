# Wattson release and deployment

## Community release

The credential-free script default intentionally matches iData's community
distribution model and does not require Developer ID credentials:

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

## Developer ID and notarization

The local script still supports an explicit Developer ID path. Set both
`WATTSON_DEVELOPER_ID_APP` and `WATTSON_DEVELOPER_ID_INSTALLER`, then set
`WATTSON_NOTARIZE=1` with either a valid notary keychain profile or all three
Team API-key variables: `WATTSON_NOTARY_KEY_PATH`, `WATTSON_NOTARY_KEY_ID`, and
`WATTSON_NOTARY_ISSUER`. Never describe an artifact as notarized unless Apple
returned `Accepted`, the notarization log contains no issues, and
`stapler validate` passed.

The unattended authenticated path is the **Wattson release candidate** GitHub
workflow. Configure a `release-signing` Environment that permits deployments
from `main` only. A required reviewer is optional; omit it when the release
must continue unattended. Store only these values in that Environment:

Secrets:

- `MACOS_APP_CERT_P12_BASE64`
- `MACOS_APP_CERT_P12_PASSWORD`
- `MACOS_INSTALLER_CERT_P12_BASE64`
- `MACOS_INSTALLER_CERT_P12_PASSWORD`
- `APPLE_NOTARY_API_KEY_P8_BASE64`
- `APPLE_NOTARY_API_KEY_ID`
- `APPLE_NOTARY_API_ISSUER_ID`

Environment variable:

- `APPLE_TEAM_ID`

The P12 files must contain the private keys for one Developer ID Application
certificate and one Developer ID Installer certificate from that Team ID. The
notary credential must be an App Store Connect **Team** API key; an Individual
API key cannot be used by `notarytool`. Keep `community-ci` free of signing
secrets.

After increasing `VERSION` and pushing the exact release commit to `main`, open
Actions, choose **Wattson release candidate**, and run it on `main`. Leave
`distribution_mode` at `developer-id-notarized`. That single dispatch imports
the credentials into a temporary keychain, signs the helper/app/PKG/DMG,
notarizes and staples the PKG and DMG, deletes the credentials, and uploads one
artifact set. Fresh GitHub-hosted macOS 14, 15, and 26 runners on Intel and
Apple silicon then install, reinstall, upgrade, launch, and uninstall those
exact bytes. A fully successful signed run automatically starts stable
promotion, Homebrew validation, public install tests, and Pages deployment.
Do not reuse or replace an existing release tag.

Pushes to `release-candidate` and manual `community-ad-hoc` runs remain
credential-free compatibility tests. They never auto-promote to a stable
release.

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

For an unattended authenticated release, push the final commit to `main`,
freeze it, and manually start the signed candidate once. Promotion rejects a
candidate unless it was manually dispatched from `main`, completed successfully,
matches the frozen `main` SHA and successful Headless CI, and reports Developer
ID signatures plus accepted/stapled notarization. Manual promotion remains an
audited fallback for the same successful candidate run ID.

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

## Maintainer Mac post-release sync

A stable release is not complete until the maintainer Mac is running the exact
public PKG bytes that passed release verification. Do not use
`scripts/install.sh` for this public-release sync; that script is only for the
user-local development build.

1. Download the stable release assets into a clean verification directory and
   verify `SHA256SUMS.txt` there with `/usr/bin/shasum -a 256 -c`.
2. Install that verified public PKG into `/Applications`:

   ```bash
   wattson_version="$(tr -d '\r\n' < VERSION)"
   verified_pkg="$PWD/dist/public-v${wattson_version}-verify/Wattson-v${wattson_version}-macos-universal.pkg"
   sudo /usr/sbin/installer -pkg "$verified_pkg" -target /
   ```

3. Require the installed marketing version, build version, and package receipt
   to equal `VERSION`, then verify the installed signature:

   ```bash
   expected_version="$(tr -d '\r\n' < VERSION)"
   info_plist="/Applications/Wattson.app/Contents/Info.plist"
   test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")" = "$expected_version"
   test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")" = "$expected_version"
   test "$(/usr/sbin/pkgutil --pkg-info com.leoarrow.wattson.pkg | /usr/bin/awk -F': ' '$1 == "version" { print $2 }')" = "$expected_version"
   /usr/bin/codesign --verify --deep --strict --verbose=2 /Applications/Wattson.app
   ```

4. Launch the installed app and confirm it stays running:

   ```bash
   /usr/bin/open -n /Applications/Wattson.app
   ```

## Local developer install

```bash
bash scripts/install.sh
```

This user-local developer path is available only when the canonical
`/Applications/Wattson.app` is absent. The script fails closed when the system
app exists so it cannot register a second app with the same bundle identifier.
Use a verified native PKG for canonical updates. Use `scripts/uninstall.sh` for
complete v2/v3 cleanup. Never replace or launch the user's installed app merely
to perform a headless build check.
