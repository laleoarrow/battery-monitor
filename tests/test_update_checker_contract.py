import pathlib
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
UPDATE_CHECKER = ROOT / "Core" / "UpdateChecker.swift"


class UpdateCheckerContractTests(unittest.TestCase):
    def test_update_checker_runtime_contract(self):
        self.assertTrue(UPDATE_CHECKER.exists(), "UpdateChecker.swift is required")
        harness = textwrap.dedent(
            r'''
            import Foundation

            func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                    exit(1)
                }
            }

            let current = UpdateVersion("3.0.13")!
            expect(UpdateVersion("v3.0.13") == current, "leading v is accepted")
            expect(UpdateVersion("3.0.14")! > current, "patch versions compare numerically")
            expect(UpdateVersion("3.0.10")! > UpdateVersion("3.0.9")!,
                   "semantic versions do not compare lexicographically")
            expect(UpdateVersion("3.1.0")! > UpdateVersion("3.0.99")!,
                   "minor versions outrank patch versions")
            expect(UpdateVersion("4.0.0")! > UpdateVersion("3.99.99")!,
                   "major versions outrank minor versions")
            expect(UpdateVersion("3.0") == nil, "two-part versions are rejected")
            expect(UpdateVersion("3.0.13-beta") == nil, "prerelease strings are rejected")
            expect(UpdateVersion("not-a-version") == nil, "invalid versions are rejected")

            func releaseData(
                tag: String,
                pageURL: String = "https://github.com/laleoarrow/battery-monitor/releases/tag/v3.0.14",
                draft: Bool = false,
                prerelease: Bool = false
            ) -> Data {
                try! JSONSerialization.data(withJSONObject: [
                    "tag_name": tag,
                    "html_url": pageURL,
                    "draft": draft,
                    "prerelease": prerelease,
                ])
            }

            let available = try! UpdateChecker.evaluate(
                data: releaseData(tag: "v3.0.14"),
                currentVersion: "3.0.13"
            )
            expect(
                available == .updateAvailable(
                    UpdateRelease(
                        version: "3.0.14",
                        pageURL: URL(
                            string: "https://github.com/laleoarrow/battery-monitor/releases/tag/v3.0.14"
                        )!
                    )
                ),
                "newer stable GitHub release is available"
            )

            let equal = try! UpdateChecker.evaluate(
                data: releaseData(tag: "v3.0.13"),
                currentVersion: "3.0.13"
            )
            expect(equal == .upToDate(currentVersion: "3.0.13"),
                   "equal release is up to date")

            let older = try! UpdateChecker.evaluate(
                data: releaseData(tag: "v3.0.12"),
                currentVersion: "3.0.13"
            )
            expect(older == .upToDate(currentVersion: "3.0.13"),
                   "an older release never asks for a downgrade")

            do {
                _ = try UpdateChecker.evaluate(
                    data: releaseData(tag: "v3.0.14", draft: true),
                    currentVersion: "3.0.13"
                )
                expect(false, "draft releases must be rejected")
            } catch UpdateCheckError.unsupportedRelease {
            } catch {
                expect(false, "draft reports the precise error")
            }

            do {
                _ = try UpdateChecker.evaluate(
                    data: releaseData(tag: "v3.0.14", prerelease: true),
                    currentVersion: "3.0.13"
                )
                expect(false, "prereleases must be rejected")
            } catch UpdateCheckError.unsupportedRelease {
            } catch {
                expect(false, "prerelease reports the precise error")
            }

            do {
                _ = try UpdateChecker.evaluate(
                    data: releaseData(tag: "v3.0.14", pageURL: "https://example.com/fake"),
                    currentVersion: "3.0.13"
                )
                expect(false, "untrusted release URLs must be rejected")
            } catch UpdateCheckError.invalidReleaseURL {
            } catch {
                expect(false, "untrusted URL reports the precise error")
            }

            enum FixtureError: Error { case offline }
            var loaderCalls = 0
            var loaderCompletion: ((Result<Data, Error>) -> Void)?
            let checker = UpdateChecker(
                currentVersion: { "3.0.13" },
                loader: { _, completion in
                    loaderCalls += 1
                    loaderCompletion = completion
                }
            )
            var completions: [UpdateCheckOutcome] = []
            var callbacksStayedOnMain = true
            checker.check { result in
                callbacksStayedOnMain = callbacksStayedOnMain && Thread.isMainThread
                if case let .success(outcome) = result { completions.append(outcome) }
            }
            checker.check { result in
                callbacksStayedOnMain = callbacksStayedOnMain && Thread.isMainThread
                if case let .success(outcome) = result { completions.append(outcome) }
            }
            expect(loaderCalls == 1, "concurrent checks share one GitHub request")
            DispatchQueue.global().async {
                loaderCompletion?(.success(releaseData(tag: "v3.0.14")))
            }
            let completionDeadline = Date().addingTimeInterval(1)
            while completions.count != 2 && Date() < completionDeadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            expect(completions.count == 2, "all coalesced callers receive the result")
            expect(callbacksStayedOnMain, "UI completions return on the main thread")

            var launchChecks = 0
            var promptedReleases: [UpdateRelease] = []
            let disabledLaunch = UpdateLaunchController(
                shouldCheck: { false },
                check: { _ in launchChecks += 1 },
                present: { promptedReleases.append($0) }
            )
            disabledLaunch.start()
            expect(launchChecks == 0, "disabled launch checking performs no request")

            var launchCompletion: ((Result<UpdateCheckOutcome, Error>) -> Void)?
            let enabledLaunch = UpdateLaunchController(
                shouldCheck: { true },
                check: { completion in
                    launchChecks += 1
                    launchCompletion = completion
                },
                present: { promptedReleases.append($0) }
            )
            enabledLaunch.start()
            expect(launchChecks == 1, "enabled launch checking performs one request")
            launchCompletion?(.success(.upToDate(currentVersion: "3.0.13")))
            expect(promptedReleases.isEmpty, "up-to-date launch checks stay quiet")
            enabledLaunch.start()
            launchCompletion?(.failure(FixtureError.offline))
            expect(promptedReleases.isEmpty, "launch network failures stay quiet")
            enabledLaunch.start()
            let release = UpdateRelease(
                version: "3.0.14",
                pageURL: URL(
                    string: "https://github.com/laleoarrow/battery-monitor/releases/tag/v3.0.14"
                )!
            )
            launchCompletion?(.success(.updateAvailable(release)))
            expect(promptedReleases == [release], "only an available update prompts on launch")
            '''
        )

        with tempfile.TemporaryDirectory(prefix="wattson-update-checker-") as temp:
            temp_path = pathlib.Path(temp)
            main = temp_path / "main.swift"
            binary = temp_path / "update-checker-contract"
            main.write_text(harness, encoding="utf-8")
            compile_result = subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    "-swift-version",
                    "5",
                    str(UPDATE_CHECKER),
                    str(main),
                    "-o",
                    str(binary),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=60,
            )
            self.assertEqual(
                compile_result.returncode,
                0,
                f"update checker contract did not compile:\n{compile_result.stderr}",
            )
            run_result = subprocess.run(
                [str(binary)],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertEqual(
                run_result.returncode,
                0,
                f"update checker contract failed:\n{run_result.stdout}{run_result.stderr}",
            )


if __name__ == "__main__":
    unittest.main()
