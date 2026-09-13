# Wattson release and deployment

## README and release notes

Keep the README focused on the product, installation, usage, and development.
Link to GitHub Releases for version-specific changes; do not append each
release's notes or unreleased-version history to the README.

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

The DMG contains `Wattson.app` and an `Applications` shortcut. Its app must match
the app inside the same candidate PKG byte for byte. The DMG installs no helper,
LaunchDaemon, socket, or package receipt: it is the drag-and-drop, read-only
monitoring route. Readings depend on available unprivileged battery telemetry;
do not promise helper-backed SMC coverage. Launch must not trigger an automatic
administrator prompt. The PKG and Homebrew remain the full app/helper route and
are required for synchronized upgrades of existing PKG installations. A plain
App replacement does not upgrade an existing helper or receipt. Older public
DMGs contain the PKG; preserve that distinction in user-facing instructions.

When Developer ID credentials are unavailable, a public community release may
still be published through the audited community path. Push one frozen commit
to `main`, require Headless CI on that exact SHA, then manually run **Wattson
release candidate** on `main` with `distribution_mode=community-ad-hoc` (the
default). Require its build and hosted install matrix to pass on the same SHA.
Download that run's artifact set, verify its manifest and checksums, and review
it before publishing those exact bytes from an annotated tag on the frozen SHA
with `--latest=false`. Do not replace existing tags or public assets. Release
notes and metadata must say app/helper ad-hoc, PKG/DMG unsigned, and not
notarized; the app-only route does not bypass Gatekeeper. Never pass community
artifacts through the signed-only `promote-release.yml` policy or describe
them as Developer ID distribution. No candidate build automatically publishes a
release, and no permanent `release-candidate` branch is used.

After publishing, synchronize the exact PKG checksum to the Homebrew tap,
require exact-tap-SHA CI and the public Homebrew lifecycle. Successful public
Intel and Apple-silicon jobs automatically mark the release latest and dispatch
Pages from the same tested `main` commit; do not duplicate those actions. This
public validation chain is shared with the signed path; only the signing and
notarization claims differ. Keep `main` frozen through the Pages gate.

## Developer ID and notarization

The local script still supports an explicit Developer ID path. Set both
`WATTSON_DEVELOPER_ID_APP` and `WATTSON_DEVELOPER_ID_INSTALLER`, then set
`WATTSON_NOTARIZE=1` with either a valid notary keychain profile or all three
Team API-key variables: `WATTSON_NOTARY_KEY_PATH`, `WATTSON_NOTARY_KEY_ID`, and
`WATTSON_NOTARY_ISSUER`. Never describe an artifact as notarized unless Apple
returned `Accepted`, the notarization log contains no issues, and
`stapler validate` passed.

The authenticated candidate path is the **Wattson release candidate** GitHub
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
Actions, choose **Wattson release candidate**, and run it on `main`. Explicitly
select `distribution_mode=developer-id-notarized`. That dispatch imports
the credentials into a temporary keychain, signs the helper/app/PKG/DMG,
notarizes and staples the PKG and DMG, deletes the credentials, and uploads one
artifact set. Fresh GitHub-hosted macOS 14, 15, and 26 runners on Intel and
Apple silicon then install, reinstall, upgrade, launch, and uninstall those
exact bytes. After reviewing a fully successful signed run, manually dispatch
`promote-release.yml` on `main` with its `candidate_run_id`. Promotion is
manual-only; its signing, notarization, exact-SHA and public validation gates
remain mandatory. Do not reuse or replace an existing release tag.

Manual `community-ad-hoc` candidates remain credential-free. They may be
published only through the separately reviewed community path above, never
through the signed promotion workflow.

## Required release gate

1. Headless SwiftPM and Python suites pass.
2. Real AppKit interaction and animation stress pass in an available GUI
   session.
3. Release artifacts build locally and their checksums verify.
4. One uploaded artifact set passes fresh-runner install, helper health,
   disabled-service reinstall, upgrade, app-process launch stability, and
   uninstall cleanup on the declared Intel/Apple-silicon macOS matrix. Also
   validate fresh DMG read-only launch without a helper, receipt or automatic
   authorization, DMG-to-PKG upgrade, and identical App bytes across both
   artifacts. The real
   menu-bar readiness path remains covered by the AppKit interaction suite on a
   battery-equipped Mac because hosted Mac mini runners have no internal battery.
5. GitHub Headless CI and the manually dispatched candidate matrix are green
   for the exact frozen `main` SHA.
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

For an authenticated release, push the final commit to `main`, freeze it, and
manually start the signed candidate once. After review, manually dispatch
promotion with that successful run ID. Promotion rejects a
candidate unless it was manually dispatched from `main`, completed successfully,
matches the frozen `main` SHA and successful Headless CI, and reports Developer
ID signatures plus accepted/stapled notarization.

If `HOMEBREW_TAP_TOKEN` is unavailable, the release workflow still downloads
and verifies every stable asset and generates the exact cask, but then fails
closed without pushing or dispatching later stages. Sync that cask from a
trusted maintainer checkout and require the separate `laleoarrow/homebrew-tap`
CI run to pass before continuing.

After a trusted manual tap sync, manually dispatch `homebrew-install-test.yml`
from `main` with the explicit release tag. No `homebrew-ready` recovery branch
is used. The workflow requires the dispatched commit to equal current remote
`main` and a successful Headless CI `push` run for that same SHA. It downloads
the stable PKG, DMG, release metadata, and checksum manifest, verifies all
checksums, requires the public cask to contain that exact version and PKG SHA,
and requires the exact public tap commit's `tests.yml` push run to have succeeded
before starting either hosted-macOS lifecycle job. The tag must match `VERSION`
at current `main`; each runner disables Homebrew auto-update and requires its
tapped repository to remain at that exact tested commit. The workflow may not
mark the release latest or dispatch Pages until both the Intel and Apple-silicon
public install/helper/uninstall lifecycles succeed.

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

## Release email to Cody

After a new stable release passes the public release gates, send Cody a concise
Chinese update email with verified release highlights, the release-page link,
direct PKG/DMG download links, and brief installation/signing guidance. Use the
confirmed recipients from the previous Wattson-to-Cody correspondence; do not
store personal email addresses in this public repository. Check Sent mail for
that version first to avoid duplicates. Send download links, not executable
attachments. Do not advertise unreleased commits as a downloadable version or
claim unmeasured accuracy, performance or energy improvements.

## Visual release overview for Cody and GitHub

For the next UI release, turn the visual review into an easy-to-browse,
version-labeled gallery with Light/Dark pairs and short power-state captions.
Include representative inline screenshots and a full-gallery link in both the
Cody release email and GitHub release notes. Use public HTTPS image/gallery
URLs, never local Markdown image paths. Verify the links without repository
authentication before sending; keep screenshot assets separate from the four
checksum-gated installer release assets unless that contract is explicitly revised.

The existing `dist/adaptive-monitoring-20260912/VISUAL-REVIEW.md` contains eight
Light/Dark state pairs from real AppKit view-owned renders with fixed fixtures,
Reduce Transparency enabled and only the top scroll viewport visible. Preserve
that evidence and label it honestly; it is not a full-window Liquid Glass or
animation demonstration. After a visual change, capture the corresponding new
build and identify its version. A Liquid Glass claim needs real composited-window
evidence (and a brief real recording for motion), not opaque captures or AI mocks.
If capture permission or evidence is unavailable, disclose that limitation and
do not change system privacy settings to obtain it.

Send this visual overview with the next validated UI release, not as an extra
duplicate notification for an already-sent release. Keep download/signing guidance
and the existing Sent-mail duplicate check. Do not overwrite old screenshots or
published installers while preparing the new presentation.

## Local developer install

```bash
bash scripts/install.sh
```

This user-local developer path is available only when the canonical
`/Applications/Wattson.app` is absent. The script fails closed when the system
app exists so it cannot register a second app with the same bundle identifier.
Use a verified native PKG to update existing full PKG installations. Use `scripts/uninstall.sh` for
complete v2/v3 cleanup. Never replace or launch the user's installed app merely
to perform a headless build check.
