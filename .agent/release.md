# Wattson release and deployment

## Local development install

```bash
cd /Users/leoarrow/Project/mypackage/agents/电池功率
bash scripts/install.sh
```

The app is installed at `~/Applications/Wattson.app`. The script builds and
ad-hoc signs the Swift/AppKit menu-bar app, installs the fixed-command helper
under `/Library/PrivilegedHelperTools`, installs its socket-activated
LaunchDaemon, and registers the app with LaunchServices.

Use `--app-only` when the helper is already current and no administrator
changes are needed:

```bash
bash scripts/install.sh --app-only
```

## Build the user DMG

```bash
cd /Users/leoarrow/Project/mypackage/agents/电池功率
bash scripts/package_dmg.sh 2.1.5
```

The result is `dist/Wattson-v2.1.5.dmg`. Its only visible item is
`Install Wattson.app`, a native graphical installer. The shipping app and the
privileged helper are sealed inside that installer instead of being exposed as
additional Finder choices.

The installer:

1. requires the signed installer to run directly from the read-only DMG and
   verifies build-pinned SHA-256 digests for every embedded payload;
2. installs the canonical app at `~/Applications/Wattson.app`;
3. asks for one standard macOS administrator authorization to install the
   helper and LaunchDaemon from a root-owned temporary staging directory;
4. removes a legacy duplicate at `/Applications/Wattson.app` only when its
   bundle identifier is `com.leoarrow.wattson`;
5. rolls the app back to its previous version if authorization or readiness
   validation fails;
6. reports success only after the helper answers over its socket and the app
   acknowledges that its real `NSStatusItem` finished initializing.

`package_dmg.sh` automatically mounts the finished image through
`scripts/verify_dmg.sh`. That check guards the original distribution failure:
the volume root must be mode `0755`, only one visible installer may exist, the
volume must carry `.metadata_never_index`, and the embedded payload must verify.

## Signing limitation

The current private build is ad-hoc signed and is not Apple-notarized. The
read-only-volume and pinned-hash checks prevent the privileged payload from
being swapped during installation, but do not authenticate the publisher.
External distribution without a Gatekeeper warning requires Developer ID signing,
hardened runtime, notarization, and ticket stapling for the exported artifacts.
Do not describe the current DMG as notarized or generally distribution-ready.
Until those credentials exist, send the printed DMG SHA-256 over an independent
trusted channel and describe the artifact only as a private test build.

## Release checks

```bash
python3 -m unittest discover -s tests -v
bash scripts/verify_dmg.sh dist/Wattson-v2.1.5.dmg
codesign --verify --deep --strict "$HOME/Applications/Wattson.app"
```

The default unittest run skips the real AppKit interaction replay because it
opens a visible popover. Run `WATTSON_RUN_INTERACTION=1 python3 -m unittest
tests.test_interaction_behavior -v` only in an idle or disposable GUI session.

For external-helper compatibility without touching the developer's Mac, push
the candidate commit and manually run the GitHub ARM64 matrix. It builds one
DMG with the macOS 26 SDK, then installs those exact bytes on fresh macOS 14, 15, and 26
runners:

```bash
gh workflow run macos-helper-install.yml --ref main -f version=2.1.5
```

Also launch the installed app, confirm that its menu-bar item and real popover
work, and verify that power-mode switching still reaches the privileged helper.

## Git release

After all checks pass and the worktree contains only the intended changes:

```bash
git add <intended files>
git commit -m "fix: add remote installer diagnostics"
git tag -a v2.1.5 -m "Wattson v2.1.5"
```

Push only when requested:

```bash
git push origin HEAD:main
git push origin v2.1.5
```
