import os
import pathlib
import shutil
import stat
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALL_HELPER = ROOT / "Installer" / "install-helper.sh"
HELPER_LABEL = "com.leoarrow.wattson.helper"


class InstallHelperBehaviorTests(unittest.TestCase):
    """Run the privileged phase against a fully redirected, local filesystem."""

    def _replace_exactly(self, source, old, new, expected_count):
        actual_count = source.count(old)
        self.assertEqual(
            actual_count,
            expected_count,
            f"update this harness for {old!r}: expected {expected_count}, found {actual_count}",
        )
        return source.replace(old, new)

    def _write_executable(self, path, contents):
        path.write_text(contents, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _make_harness(self, directory):
        sandbox = pathlib.Path(directory)
        installer = sandbox / "Installer"
        payload = installer / "Payload"
        fake_bin = sandbox / "fake-bin"
        state = sandbox / "launchctl-state"
        root = sandbox / "system"
        payload.mkdir(parents=True)
        fake_bin.mkdir()
        state.mkdir()

        helper_bin = root / "PrivilegedHelperTools" / HELPER_LABEL
        helper_plist = root / "LaunchDaemons" / f"{HELPER_LABEL}.plist"
        helper_socket = root / "run" / "wattson-helper.sock"
        source = INSTALL_HELPER.read_text(encoding="utf-8")
        replacements = (
            ("/Library/LaunchDaemons", str(root / "LaunchDaemons"), 1),
            ("/Library/PrivilegedHelperTools", str(root / "PrivilegedHelperTools"), 2),
            ("/var/run", str(root / "run"), 1),
            ("/Applications", str(root / "legacy-apps"), 3),
            ("/bin/launchctl", str(fake_bin / "launchctl"), 14),
            ("/usr/bin/install", str(fake_bin / "install"), 8),
            ("/usr/bin/xattr", str(fake_bin / "xattr"), 3),
            ("/usr/bin/codesign", str(fake_bin / "codesign"), 1),
            ("/usr/bin/id", str(fake_bin / "id"), 1),
            ("/usr/bin/plutil", str(fake_bin / "plutil"), 1),
            ("/usr/bin/pkill", str(fake_bin / "pkill"), 1),
            ("/usr/libexec/PlistBuddy", str(fake_bin / "PlistBuddy"), 4),
            ("/bin/rm", str(fake_bin / "rm"), 6),
            ("/bin/mv", str(fake_bin / "mv"), 4),
            ("/bin/sleep", str(fake_bin / "sleep"), 2),
            (
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
                "LaunchServices.framework/Support/lsregister",
                str(fake_bin / "lsregister"),
                1,
            ),
        )
        for old, new, expected_count in replacements:
            source = self._replace_exactly(source, old, new, expected_count)

        # This check must happen before the transformed script is executable:
        # any missed replacement could otherwise modify the developer machine.
        for forbidden in (
            "/Library/LaunchDaemons",
            "/Library/PrivilegedHelperTools",
            "/var/run",
            "/Applications",
            "/bin/launchctl",
        ):
            self.assertNotIn(forbidden, source)

        script = installer / "install-helper.sh"
        self._write_executable(script, source)
        self._write_executable(
            payload / HELPER_LABEL,
            """#!/bin/bash
if [[ "${1:-}" == "--health-probe" ]]; then
    /usr/bin/touch "$FAKE_LAUNCHCTL_STATE/health-probe"
    exit "${FAKE_HEALTH_PROBE_STATUS:-0}"
fi
exit 0
""",
        )
        shutil.copyfile(ROOT / "Helper" / f"{HELPER_LABEL}.plist", payload / f"{HELPER_LABEL}.plist")

        self._write_executable(
            fake_bin / "install",
            """#!/bin/bash
set -euo pipefail
if [[ "$1" == "-d" ]]; then
    /bin/mkdir -p -- "${!#}"
    exit 0
fi
source_path="${@: -2:1}"
destination="${!#}"
/bin/mkdir -p -- "$(/usr/bin/dirname -- "$destination")"
/bin/cp -- "$source_path" "$destination"
if quarantine="$(/usr/bin/xattr -p com.apple.quarantine "$source_path" 2>/dev/null)"; then
    /usr/bin/xattr -w com.apple.quarantine "$quarantine" "$destination"
fi
""",
        )
        for command in ("codesign", "plutil", "pkill", "lsregister"):
            self._write_executable(fake_bin / command, "#!/bin/bash\nexit 0\n")
        self._write_executable(fake_bin / "id", "#!/bin/bash\nprintf '0\\n'\n")
        self._write_executable(
            fake_bin / "xattr",
            """#!/bin/bash
if [[ "${FAKE_XATTR_LIST_FAILURE:-0}" == "1" && "$#" == "1" ]]; then
    exit 74
fi
exec /usr/bin/xattr "$@"
""",
        )
        self._write_executable(
            fake_bin / "PlistBuddy",
            """#!/bin/bash
case "$2" in
    'Print :Label') printf '%s\\n' "$FAKE_HELPER_LABEL" ;;
    'Print :ProgramArguments:0') printf '%s\\n' "$FAKE_HELPER_BIN" ;;
    'Print :Sockets:Listener:SockPathName') printf '%s\\n' "$FAKE_HELPER_SOCKET" ;;
    *) exit 2 ;;
esac
""",
        )
        self._write_executable(fake_bin / "rm", "#!/bin/bash\nexec /bin/rm \"$@\"\n")
        self._write_executable(fake_bin / "mv", "#!/bin/bash\nexec /bin/mv \"$@\"\n")
        self._write_executable(fake_bin / "sleep", "#!/bin/bash\nexit 0\n")
        self._write_executable(
            fake_bin / "launchctl",
            """#!/bin/bash
set -euo pipefail
state="$FAKE_LAUNCHCTL_STATE"
command="$1"
shift
printf '%s %s\\n' "$command" "$*" >> "$state/commands"
loaded() { [[ -f "$state/loaded" && "$(<"$state/loaded")" == "1" ]]; }
disabled() { [[ -f "$state/disabled" && "$(<"$state/disabled")" == "1" ]]; }
case "$command" in
    print-disabled)
        if disabled; then
            printf '\"%s\" => disabled\\n' "$FAKE_HELPER_LABEL"
        fi
        ;;
    print)
        if [[ -f "$state/delayed-load" ]]; then
            delayed_state="$(<"$state/delayed-load")"
            if [[ "$delayed_state" == "0" ]]; then
                printf '1\\n' > "$state/delayed-load"
                exit 1
            fi
            /bin/rm -f -- "$state/delayed-load"
            printf '1\\n' > "$state/loaded"
        fi
        loaded
        ;;
    bootout)
        bootout_attempts=0
        [[ -f "$state/bootout-attempts" ]] && bootout_attempts="$(<"$state/bootout-attempts")"
        bootout_attempts=$((bootout_attempts + 1))
        printf '%s\\n' "$bootout_attempts" > "$state/bootout-attempts"
        if (( bootout_attempts > FAKE_BOOTOUT_STUCK_ATTEMPTS )); then
            printf '0\\n' > "$state/loaded"
        fi
        ;;
    enable)
        printf '0\\n' > "$state/disabled"
        ;;
    disable)
        printf '1\\n' > "$state/disabled"
        ;;
    bootstrap)
        attempts=0
        [[ -f "$state/bootstrap-attempts" ]] && attempts="$(<"$state/bootstrap-attempts")"
        attempts=$((attempts + 1))
        printf '%s\\n' "$attempts" > "$state/bootstrap-attempts"
        if (( attempts <= FAKE_BOOTSTRAP_EIO_ATTEMPTS )); then
            if [[ "$FAKE_EIO_AFTER_LOAD" == "1" ]]; then
                printf '1\\n' > "$state/loaded"
            elif [[ "$FAKE_DELAYED_LOAD_AFTER_EIO" == "1" ]]; then
                printf '0\\n' > "$state/delayed-load"
            fi
            printf 'bootstrap: Input/output error\\n' >&2
            exit 5
        fi
        printf '1\\n' > "$state/loaded"
        ;;
    *)
        printf 'unexpected launchctl command: %s\\n' "$command" >&2
        exit 2
        ;;
esac
""",
        )

        environment = os.environ.copy()
        environment.update(
            {
                "FAKE_LAUNCHCTL_STATE": str(state),
                "FAKE_BOOTSTRAP_EIO_ATTEMPTS": "0",
                "FAKE_BOOTOUT_STUCK_ATTEMPTS": "0",
                "FAKE_DELAYED_LOAD_AFTER_EIO": "0",
                "FAKE_EIO_AFTER_LOAD": "0",
                "FAKE_HEALTH_PROBE_STATUS": "0",
                "FAKE_XATTR_LIST_FAILURE": "0",
                "FAKE_HELPER_LABEL": HELPER_LABEL,
                "FAKE_HELPER_BIN": str(helper_bin),
                "FAKE_HELPER_SOCKET": str(helper_socket),
            }
        )
        return {
            "environment": environment,
            "helper_bin": helper_bin,
            "helper_plist": helper_plist,
            "payload_helper": payload / HELPER_LABEL,
            "payload_plist": payload / f"{HELPER_LABEL}.plist",
            "script": script,
            "state": state,
        }

    def _run(
        self,
        harness,
        bootstrap_eio_attempts=0,
        *,
        bootout_stuck_attempts=0,
        delayed_load_after_eio=False,
        eio_after_load=False,
        health_probe_status=0,
        xattr_list_failure=False,
    ):
        environment = harness["environment"].copy()
        environment["FAKE_BOOTSTRAP_EIO_ATTEMPTS"] = str(bootstrap_eio_attempts)
        environment["FAKE_BOOTOUT_STUCK_ATTEMPTS"] = str(bootout_stuck_attempts)
        environment["FAKE_DELAYED_LOAD_AFTER_EIO"] = (
            "1" if delayed_load_after_eio else "0"
        )
        environment["FAKE_EIO_AFTER_LOAD"] = "1" if eio_after_load else "0"
        environment["FAKE_HEALTH_PROBE_STATUS"] = str(health_probe_status)
        environment["FAKE_XATTR_LIST_FAILURE"] = "1" if xattr_list_failure else "0"
        return subprocess.run(
            ["/bin/bash", str(harness["script"])],
            check=False,
            cwd=harness["script"].parent,
            env=environment,
            text=True,
            capture_output=True,
        )

    def _commands(self, harness):
        commands = harness["state"] / "commands"
        return commands.read_text(encoding="utf-8").splitlines() if commands.exists() else []

    def _write_old_installation(self, harness, *, loaded=False, disabled=False):
        harness["helper_bin"].parent.mkdir(parents=True, exist_ok=True)
        harness["helper_plist"].parent.mkdir(parents=True, exist_ok=True)
        harness["helper_bin"].write_text("old helper", encoding="utf-8")
        harness["helper_plist"].write_text("old plist", encoding="utf-8")
        (harness["state"] / "loaded").write_text("1" if loaded else "0", encoding="utf-8")
        (harness["state"] / "disabled").write_text("1" if disabled else "0", encoding="utf-8")

    def test_first_install_bootstraps_and_starts_the_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = self._make_harness(directory)
            result = self._run(harness)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(harness["helper_bin"].is_file())
            self.assertTrue(harness["helper_plist"].is_file())
            self.assertEqual((harness["state"] / "loaded").read_text(encoding="utf-8"), "1\n")
            commands = self._commands(harness)
            self.assertIn(f"bootstrap system {harness['helper_plist']}", commands)
            self.assertFalse(any(command.startswith("bootout ") for command in commands))

    def test_disabled_existing_service_is_enabled_before_bootstrap(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = self._make_harness(directory)
            self._write_old_installation(harness, disabled=True)
            result = self._run(harness)

            self.assertEqual(result.returncode, 0, result.stderr)
            commands = self._commands(harness)
            self.assertLess(
                commands.index(f"enable system/{HELPER_LABEL}"),
                commands.index(f"bootstrap system {harness['helper_plist']}"),
            )
            self.assertEqual((harness["state"] / "disabled").read_text(encoding="utf-8"), "0\n")

    def test_loaded_stale_service_is_booted_out_before_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = self._make_harness(directory)
            self._write_old_installation(harness, loaded=True)
            result = self._run(harness)

            self.assertEqual(result.returncode, 0, result.stderr)
            commands = self._commands(harness)
            self.assertLess(
                commands.index(f"bootout system/{HELPER_LABEL}"),
                commands.index(f"bootstrap system {harness['helper_plist']}"),
            )
            self.assertIn(
                "--health-probe", harness["helper_bin"].read_text(encoding="utf-8")
            )

    def test_bootstrap_eio_rolls_back_a_first_install(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = self._make_harness(directory)
            result = self._run(harness, bootstrap_eio_attempts=2)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Input/output error", result.stderr)
            self.assertFalse(harness["helper_bin"].exists())
            self.assertFalse(harness["helper_plist"].exists())
            loaded_state = harness["state"] / "loaded"
            self.assertTrue(
                not loaded_state.exists()
                or loaded_state.read_text(encoding="utf-8").strip() == "0"
            )

    def test_bootstrap_eio_restores_the_previous_files_and_disabled_state(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = self._make_harness(directory)
            self._write_old_installation(harness, loaded=True, disabled=True)

            result = self._run(harness, bootstrap_eio_attempts=2)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(harness["helper_bin"].read_text(encoding="utf-8"), "old helper")
            self.assertEqual(harness["helper_plist"].read_text(encoding="utf-8"), "old plist")
            self.assertEqual(
                (harness["state"] / "loaded").read_text(encoding="utf-8").strip(), "1"
            )
            self.assertEqual(
                (harness["state"] / "disabled").read_text(encoding="utf-8").strip(), "1"
            )
            commands = self._commands(harness)
            rollback_enable = len(commands) - 1 - commands[::-1].index(
                f"enable system/{HELPER_LABEL}"
            )
            rollback_bootstrap = len(commands) - 1 - commands[::-1].index(
                f"bootstrap system {harness['helper_plist']}"
            )
            rollback_disable = len(commands) - 1 - commands[::-1].index(
                f"disable system/{HELPER_LABEL}"
            )
            self.assertLess(rollback_enable, rollback_bootstrap)
            self.assertLess(rollback_bootstrap, rollback_disable)

    def test_transient_bootstrap_eio_is_retried_and_then_succeeds(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = self._make_harness(directory)
            result = self._run(harness, bootstrap_eio_attempts=1)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                (harness["state"] / "bootstrap-attempts").read_text(encoding="utf-8"), "2\n"
            )
            self.assertTrue(harness["helper_bin"].is_file())
            self.assertTrue(harness["helper_plist"].is_file())

    def test_bootstrap_error_after_registration_uses_the_health_probe_as_truth(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = self._make_harness(directory)

            result = self._run(harness, bootstrap_eio_attempts=1, eio_after_load=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                (harness["state"] / "bootstrap-attempts").read_text(encoding="utf-8"),
                "1\n",
            )
            self.assertTrue((harness["state"] / "health-probe").exists())

    def test_health_probe_failure_rolls_back_after_bootstrap_reported_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = self._make_harness(directory)

            result = self._run(
                harness,
                bootstrap_eio_attempts=1,
                eio_after_load=True,
                health_probe_status=70,
            )

            self.assertEqual(result.returncode, 70)
            self.assertTrue((harness["state"] / "health-probe").exists())
            self.assertFalse(harness["helper_bin"].exists())
            self.assertFalse(harness["helper_plist"].exists())

    def test_retry_stops_if_a_delayed_job_cannot_be_booted_out(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = self._make_harness(directory)

            result = self._run(
                harness,
                bootstrap_eio_attempts=2,
                delayed_load_after_eio=True,
                bootout_stuck_attempts=1,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(
                (harness["state"] / "bootstrap-attempts").read_text(encoding="utf-8"),
                "1\n",
            )
            self.assertFalse(harness["helper_bin"].exists())
            self.assertFalse(harness["helper_plist"].exists())

    def test_quarantine_is_removed_from_verified_install_candidates(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = self._make_harness(directory)
            quarantine = b"0081;00000000;Safari;"
            for payload_path in (harness["payload_helper"], harness["payload_plist"]):
                subprocess.run(
                    [
                        "/usr/bin/xattr",
                        "-w",
                        "com.apple.quarantine",
                        quarantine.decode("ascii"),
                        str(payload_path),
                    ],
                    check=True,
                )

            result = self._run(harness)

            self.assertEqual(result.returncode, 0, result.stderr)
            for installed_path in (harness["helper_bin"], harness["helper_plist"]):
                attributes = subprocess.run(
                    ["/usr/bin/xattr", str(installed_path)],
                    check=True,
                    text=True,
                    capture_output=True,
                ).stdout.splitlines()
                self.assertNotIn("com.apple.quarantine", attributes)

    def test_extended_attribute_query_failure_stops_before_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            harness = self._make_harness(directory)

            result = self._run(harness, xattr_list_failure=True)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("extended attributes could not be inspected", result.stderr)
            self.assertFalse(harness["helper_bin"].exists())
            self.assertFalse(harness["helper_plist"].exists())


if __name__ == "__main__":
    unittest.main()
