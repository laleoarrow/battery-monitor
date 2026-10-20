import pathlib
from local_runtime import TemporaryDirectory, run
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class SystemBatteryHealthRuntimeTests(unittest.TestCase):
    def test_real_reader_handles_output_exit_and_deadline_boundaries(self):
        harness = textwrap.dedent(
            r'''
            import Darwin
            import Foundation

            func require(_ condition: @autoclosure () -> Bool, _ message: String) {
                if !condition() {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                    exit(1)
                }
            }

            let report = Data("""
            {"SPPowerDataType":[{"_name":"spbattery_information",
            "sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"84%"}}]}
            """.utf8)

            if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--fixture" {
                let mode = CommandLine.arguments[2]
                if mode == "ignore-term" { signal(SIGTERM, SIG_IGN) }
                try String(getpid()).write(toFile: CommandLine.arguments[3],
                                           atomically: true, encoding: .utf8)
                switch mode {
                case "split":
                    let midpoint = report.count / 2
                    FileHandle.standardOutput.write(report.prefix(midpoint))
                    usleep(30_000)
                    FileHandle.standardOutput.write(report.suffix(from: midpoint))
                case "nonzero":
                    FileHandle.standardOutput.write(report)
                    _exit(7)
                case "at-limit", "over-limit":
                    let count = mode == "at-limit" ? 262_144 : 262_145
                    var output = report
                    output.append(Data(repeating: 32, count: count - report.count))
                    FileHandle.standardOutput.write(output)
                case "sleep", "ignore-term":
                    while true { pause() }
                default:
                    _exit(8)
                }
                _exit(0)
            }

            let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let cases: [(String, Double?)] = [
                ("split", 84), ("nonzero", nil), ("at-limit", 84),
                ("over-limit", nil), ("sleep", nil), ("ignore-term", nil),
            ]
            for (mode, expected) in cases {
                let pidFile = directory.appendingPathComponent(mode + ".pid")
                let actual = SystemBatteryHealth.readPercentForTest(
                    executableURL: executable,
                    arguments: ["--fixture", mode, pidFile.path],
                    budgetNanoseconds: mode == "sleep" || mode == "ignore-term"
                        ? 600_000_000 : 5_000_000_000
                )
                require(actual == expected, "\(mode): unexpected health result")
                let text = try String(contentsOf: pidFile, encoding: .utf8)
                require(Int32(text) != nil, "\(mode): fixture did not publish its PID")
                let pid = Int32(text)!
                errno = 0
                require(kill(pid, 0) == -1 && errno == ESRCH,
                        "\(mode): direct child was not reaped before return")
            }
            let failedLaunch = SystemBatteryHealth.readPercentForTest(
                executableURL: directory.appendingPathComponent("missing-executable"),
                arguments: [], budgetNanoseconds: 600_000_000
            )
            require(failedLaunch == nil, "failed launch must remain unavailable")
            print("battery health runtime passed: 6 children reaped, launch failure handled")
            '''
        )
        workspace = TemporaryDirectory(prefix="battery-health-")
        directory_path = pathlib.Path(workspace.name)
        with workspace:
            main = directory_path / "main.swift"
            binary = directory_path / "battery-health-runtime"
            main.write_text(harness, encoding="utf-8")
            compile_result = run(
                [
                    "/usr/bin/xcrun", "swiftc", "-D", "DEBUG", "-swift-version", "5",
                    str(ROOT / "Core" / "SystemBatteryHealth.swift"), str(main),
                    "-o", str(binary),
                ],
                capture_output=True, text=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = run(
                [str(binary), str(directory_path)], capture_output=True,
                text=True, timeout=15,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("6 children reaped, launch failure handled", result.stdout)
            self.assertEqual(len(list(directory_path.glob("*.pid"))), 6)
        self.assertFalse(directory_path.exists(), "runtime workspace must be removed")
        self.assertFalse(workspace.processes, "runtime must release all owned process groups")


if __name__ == "__main__":
    unittest.main()
