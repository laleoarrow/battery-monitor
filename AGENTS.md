# Battery Power Monitor agent guide

This project is the native AppKit Wattson menu-bar battery power monitor built
with Swift.

## Read first

- Start with `.agent/README.md`.
- Use `.agent/project.md` for architecture and key files.
- Use `.agent/debugging.md` for runtime debugging, layout fixes, and verification.
- Use `.agent/release.md` for packaging, install/deployment steps, and release tagging.

## Project rules

- Metrics shared with macOS must prioritize Apple's system-reported values and
  states. Battery health means macOS Maximum Capacity (%), never raw full-charge
  capacity divided by design capacity. Missing official health stays unavailable;
  sensor measurements and Wattson estimates must identify their different meaning.
- All project code and assets must live under `/Users/leoarrow/Project/mypackage/agents/电池功率`.
- The canonical user-facing app is `/Applications/Wattson.app`, installed by
  the native PKG together with its privileged helper and package receipt.
- `battery_monitor.py`, `~/.battery_monitor.py`, and
  `~/Applications/电池功率.app` are retired v2 reference/migration surfaces.
  Never copy or launch them as the current product.
- `scripts/install.sh` is only a user-local developer build. It must fail
  closed while `/Applications/Wattson.app` exists so a second app with the same
  bundle identifier cannot be registered. Use a verified release PKG to update
  the canonical installation.
- Verify AppKit layout changes with the real production renderers and the
  charging, full, on-battery, mixed-supply, low-battery, and Low Power states.
  Use the disposable ARM GUI test VM when visible interaction would interfere
  with the user's desktop.
- Keep git repository status clean and update tags/commits appropriately.
- Run Swift tests through `scripts/test_swift.sh`. Create preference domains
  with `testDefaultsSuite` or register injected domains with
  `registerTestDefaultsSuite` before use. The parent cleans this run's exact
  domains after the test process exits, including failure and interruption.
- Every build/test entrypoint must own and automatically clean its temporary
  files, app registrations, test preferences, newly created test containers,
  child processes, and mounts on success, failure, timeout, and catchable
  interruption. Use the shared lifecycle helpers; never rely on the next run
  to delete the previous run's outputs. Preserve final distribution artifacts
  and explicit caller-owned inputs. Keep scratch under project-local `.noindex`
  directories. Never clean the canonical installation or production user data.
