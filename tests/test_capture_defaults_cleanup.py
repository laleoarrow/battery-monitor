import pathlib
import shutil
import unittest

from local_runtime import TemporaryDirectory, run

ROOT = pathlib.Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('xcrun'), 'requires Swift')
class CaptureDefaultsCleanupTests(unittest.TestCase):
    def test_both_capture_hosts_keep_preferences_in_memory(self):
        for name in ('capture_real_settings.swift', 'capture_runtime_sections.swift'):
            with self.subTest(source=name), TemporaryDirectory(prefix='capture-defaults-') as temp:
                root = pathlib.Path(temp)
                source = (ROOT / 'Tests/visual' / name).read_text()
                defaults = 'private final class CaptureDefaults' + source.split(
                    'private final class CaptureDefaults', 1
                )[1]
                main = root / 'main.swift'
                main.write_text('import Foundation\n' + defaults + '''
let key = "Wattson.CaptureDefaults.Probe.\\(UUID().uuidString)"
private let first = CaptureDefaults()
private let independent = CaptureDefaults()
first.set(true, forKey: key)
precondition(first.bool(forKey: key))
precondition(independent.object(forKey: key) == nil)
precondition(UserDefaults.standard.object(forKey: key) == nil)
first.set("fixture", forKey: key)
precondition(first.string(forKey: key) == "fixture")
first.removeObject(forKey: key)
precondition(first.isEmpty)
first.set(42, forKey: key)
precondition(first.integer(forKey: key) == 42)
first.clear()
precondition(first.isEmpty)
print("CAPTURE_DEFAULTS_MEMORY_ONLY")
''')
                binary = root / 'probe'
                compiled = run(['xcrun', 'swiftc', str(main), '-o', str(binary)],
                               capture_output=True, text=True)
                self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
                result = run([str(binary)], check=True, capture_output=True, text=True)
                self.assertIn('CAPTURE_DEFAULTS_MEMORY_ONLY', result.stdout)
                self.assertNotIn('UserDefaults(suiteName:', source)


if __name__ == '__main__':
    unittest.main()
