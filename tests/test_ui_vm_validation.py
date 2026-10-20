import json
import os
import pathlib
import unittest

import local_runtime as runtime


ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "tests/performance/ui_vm.py"
GUEST = ROOT / "tests/performance/ui-vm-guest.sh"


class UIVMValidationTests(unittest.TestCase):
    def setUp(self):
        self.workspace = runtime.TemporaryDirectory(prefix="ui_vm_validation-")
        self.addCleanup(self.workspace.cleanup)
        self.root = pathlib.Path(self.workspace.name)

    def python_modes(self):
        return (([], {"PYTHONOPTIMIZE": "0"}), (["-O"], {"PYTHONOPTIMIZE": "0"}),
                ([], {"PYTHONOPTIMIZE": "1"}))

    def test_invalid_vm_state_rejected_even_with_python_optimization(self):
        before = self.root / "before.json"
        before.write_text(json.dumps([
            {"Name": "macOS-TestLab", "State": "running", "Running": True},
            {"Name": "macOS-TestLab-Base", "State": "stopped", "Running": False},
        ]))
        for flags, overrides in self.python_modes():
            with self.subTest(flags=flags, overrides=overrides):
                result = runtime.run(
                    ["/usr/bin/python3", *flags, str(HELPER), "preflight", "Owned-Test-VM", str(before)],
                    env=dict(os.environ, **overrides), capture_output=True, text=True, timeout=5,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("TestLab/Base is in use", result.stderr)
        after = self.root / "after.json"
        after.write_text(before.read_text().replace('"running"', '"stopped"').replace('true', 'false'))
        result = runtime.run(
            ["/usr/bin/python3", "-O", str(HELPER), "after", "Owned-Test-VM", str(before), str(after)],
            capture_output=True, text=True, timeout=5,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unrelated VM state changed", result.stderr)

    def test_guest_rejects_bad_archive_and_patch_hash_with_python_optimization(self):
        code = GUEST.read_text().split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        share = self.root / "share"
        share.mkdir()
        (share / "results").mkdir()
        (share / "tools.tar.gz").write_bytes(b"invalid archive; must reject before extraction")
        (share / "diagnostic.patch").write_bytes(b"invalid patch; must reject before application")
        for kind in ("archive", "patch"):
            manifest = {"archives": {}, "sources": {}}
            if kind == "archive":
                manifest["archives"]["tools.tar.gz"] = "0" * 64
            else:
                manifest["diagnosticPatchSHA256"] = "0" * 64
            (share / "manifest.json").write_text(json.dumps(manifest))
            for index, (flags, overrides) in enumerate(self.python_modes()):
                with self.subTest(kind=kind, flags=flags, overrides=overrides):
                    destination = self.root / f"{kind}-{index}"
                    destination.mkdir()
                    result = runtime.run(
                        ["/usr/bin/python3", *flags, "-c", code, str(share), str(destination)],
                        env=dict(os.environ, **overrides), capture_output=True, text=True, timeout=5,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("SHA-256 mismatch", result.stderr)

    def test_uninstrumented_success_cannot_pass_diagnostic_gate(self):
        result = self.root / "result.jsonl"
        result.write_text('\n'.join(json.dumps(row) for row in [
            {"type": "environment"}, {"type": "complete"},
        ]) + '\n')
        completed = runtime.run(
            ["/usr/bin/python3", "-O", str(HELPER), "verify-result", str(result), "1"],
            capture_output=True, text=True, timeout=5,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("Diagnostic metadata/traces missing", completed.stderr)

    def test_existing_broken_output_symlink_is_rejected_before_vm_access(self):
        output = self.root / "output"
        output.symlink_to(self.root / "missing")
        result = runtime.run(
            ["/bin/bash", str(ROOT / "scripts/measure_ui_vm.sh"), str(output), "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 64)
        self.assertTrue(output.is_symlink())
        self.assertFalse((self.root / "missing").exists())


if __name__ == "__main__":
    unittest.main()
