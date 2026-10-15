import Foundation
import Darwin
import XCTest

extension UserDefaults {
    /// Removing a domain can leave an empty plist in the real user preferences.
    func removePersistentTestDomain(
        forName domain: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard domain.range(
            of: #"^Wattson\.SwiftTests\.[A-Za-z]+\.[A-Fa-f0-9-]{36}$"#,
            options: .regularExpression
        ) != nil, UUID(uuidString: String(domain.suffix(36))) != nil else {
            XCTFail("Refusing to remove a non-test preferences domain: \(domain)", file: file, line: line)
            return
        }
        removePersistentDomain(forName: domain)
        guard synchronize() else {
            XCTFail("Could not synchronize removed test domain: \(domain)", file: file, line: line)
            return
        }
        // Tell cfprefsd to forget the domain before deleting a leftover empty
        // plist; synchronizing UserDefaults alone can later recreate it.
        let deletion = Process()
        let completed = DispatchSemaphore(value: 0)
        let errors = Pipe()
        deletion.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        deletion.arguments = ["delete", domain]
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
        guard deletion.terminationStatus == 0 || errorText.contains("Domain (\(domain)) not found.") else {
            XCTFail("Could not delete test domain: \(errorText)", file: file, line: line)
            return
        }
        let preference = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(domain).plist")
        do {
            try FileManager.default.removeItem(at: preference)
        } catch CocoaError.fileNoSuchFile {
            // cfprefsd may already have removed the file.
        } catch {
            XCTFail("Could not remove test preferences: \(error)", file: file, line: line)
        }
    }
}

final class TestDefaultsCleanupTests: XCTestCase {
    func testPersistedSuiteFileStaysRemovedAfterDaemonReads() throws {
        let suite = "Wattson.SwiftTests.Cleanup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentTestDomain(forName: suite) }
        let preference = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suite).plist")
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
