import Foundation
import Darwin
import XCTest

private func isTestDefaultsSuite(_ domain: String) -> Bool {
    domain.range(
        of: #"^Wattson\.SwiftTests\.[A-Za-z]+\.[A-Fa-f0-9-]{36}$"#,
        options: .regularExpression
    ) != nil && UUID(uuidString: String(domain.suffix(36))) != nil
}

func testDefaultsSuite(_ feature: String) -> String {
    registerTestDefaultsSuite("Wattson.SwiftTests.\(feature).\(UUID().uuidString)")
}

private func rejectTestDefaultsSetup(_ reason: String) -> Never {
    FileHandle.standardError.write(Data("Test preferences setup failed: \(reason)\n".utf8))
    exit(EXIT_FAILURE)
}

func registerTestDefaultsSuite(_ domain: String) -> String {
    guard isTestDefaultsSuite(domain) else {
        rejectTestDefaultsSetup("Refusing a non-test preferences domain")
    }
    guard let path = ProcessInfo.processInfo.environment["WATTSON_TEST_DEFAULTS_MANIFEST"] else {
        rejectTestDefaultsSetup("Run tests with bash scripts/test_swift.sh to own their cleanup")
    }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    do {
        let properties = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard properties.isDirectory == true && properties.isSymbolicLink != true else {
            rejectTestDefaultsSetup("Test preferences manifest must be an owned directory")
        }
        // Register before UserDefaults can write, including when a test
        // exits without reaching its tearDown or defer.
        try Data().write(to: directory.appendingPathComponent(domain), options: .atomic)
    } catch {
        rejectTestDefaultsSetup("Could not register test preferences: \(error)")
    }
    return domain
}

func testPreferencesFile(for domain: String) -> URL {
    // CFFIXED_USER_HOME changes Foundation's home URL, but cfprefsd still
    // writes these suites to the account's actual home directory.
    guard let account = getpwuid(getuid()) else {
        preconditionFailure("Could not resolve the test user's home directory")
    }
    return URL(fileURLWithPath: String(cString: account.pointee.pw_dir), isDirectory: true)
        .appendingPathComponent("Library/Preferences/\(domain).plist")
}

extension UserDefaults {
    /// Removing a domain can leave an empty plist in the real user preferences.
    func removePersistentTestDomain(
        forName domain: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard isTestDefaultsSuite(domain) else {
            XCTFail("Refusing to remove a non-test preferences domain: \(domain)", file: file, line: line)
            return
        }
        let preference = testPreferencesFile(for: domain)
        defer {
            do {
                try FileManager.default.removeItem(at: preference)
            } catch CocoaError.fileNoSuchFile {
                // cfprefsd may already have removed the file.
            } catch {
                XCTFail("Could not remove test preferences: \(error)", file: file, line: line)
            }
        }
        removePersistentDomain(forName: domain)
        if !synchronize() {
            XCTFail("Could not synchronize removed test domain: \(domain)", file: file, line: line)
        }
        // Tell cfprefsd to forget the domain before deleting a leftover empty
        // plist; synchronizing UserDefaults alone can later recreate it.
        let deletion = Process()
        let completed = DispatchSemaphore(value: 0)
        let errors = Pipe()
        deletion.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        deletion.arguments = ["delete", domain]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CFFIXED_USER_HOME")
        environment["LC_ALL"] = "C"
        deletion.environment = environment
        deletion.standardOutput = FileHandle.nullDevice
        deletion.standardError = errors
        deletion.terminationHandler = { _ in completed.signal() }
        do {
            try deletion.run()
        } catch {
            XCTFail("Could not delete test domain through cfprefsd: \(error)", file: file, line: line)
            return
        }
        guard completed.wait(timeout: .now() + 3) == .success else {
            deletion.terminate()
            if completed.wait(timeout: .now() + 0.5) != .success {
                _ = Darwin.kill(deletion.processIdentifier, SIGKILL)
                _ = completed.wait(timeout: .now() + 1)
            }
            XCTFail("Timed out deleting test domain: \(domain)", file: file, line: line)
            return
        }
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard deletion.terminationStatus == 0
                || errorText.contains("Domain (\(domain)) not found.")
                || errorText.contains("Domain '\(domain)' not found.") else {
            XCTFail("Could not delete test domain: \(errorText)", file: file, line: line)
            return
        }
    }
}

final class TestDefaultsCleanupTests: XCTestCase {
    func testPersistedSuiteFileStaysRemovedAfterDaemonReads() throws {
        let suite = testDefaultsSuite("Cleanup")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentTestDomain(forName: suite) }
        let preference = testPreferencesFile(for: suite)
        defaults.set("fixture", forKey: "probe")
        XCTAssertTrue(defaults.synchronize())
        XCTAssertTrue(FileManager.default.fileExists(atPath: preference.path))

        defaults.removePersistentTestDomain(forName: suite)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preference.path))
        for _ in 0..<5 {
            let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
            XCTAssertNil(reopened.object(forKey: "probe"))
            XCTAssertTrue(reopened.synchronize())
            Thread.sleep(forTimeInterval: 0.2)
            XCTAssertFalse(FileManager.default.fileExists(atPath: preference.path))
        }
    }
}
