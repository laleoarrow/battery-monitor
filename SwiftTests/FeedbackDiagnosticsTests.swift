import Foundation
import XCTest
@testable import Wattson

final class FeedbackDiagnosticsTests: XCTestCase {
    func testBatteryAllowlistExcludesIdentityAndRejectsNonNumericValues() {
        let fields = FeedbackDiagnostics.safeBatteryValues([
            "CurrentCapacity": NSNumber(value: 58),
            "Voltage": "private-value",
            "InstantAmperage": NSNumber(value: -2300),
            "AvgTimeToEmpty": 120,
            "AvgTimeToFull": 65535,
            "Temperature": NSNumber(value: Double.infinity),
            "SerialNumber": "private-value",
            "BatterySerialNumber": "private-value",
            "UserName": "private-value",
            "PowerTelemetryData": [
                "SystemLoad": NSNumber(value: 17500),
                "BatteryPower": ["serial": "private-value"],
                "SerialNumber": "private-value",
            ],
        ])

        XCTAssertEqual(fields["CurrentCapacity"], "58")
        XCTAssertEqual(fields["InstantAmperage"], "-2300")
        XCTAssertEqual(fields["AvgTimeToEmpty"], "120")
        XCTAssertEqual(fields["AvgTimeToFull"], "65535")
        XCTAssertEqual(fields["PowerTelemetryData.SystemLoad"], "17500")
        XCTAssertEqual(fields["Voltage"], "unavailable")
        XCTAssertEqual(fields["Temperature"], "unavailable")
        XCTAssertEqual(fields["PowerTelemetryData.BatteryPower"], "unavailable")
        XCTAssertFalse(fields.keys.contains { $0.contains("Serial") || $0.contains("UserName") })
        XCTAssertFalse(fields.values.contains { $0.contains("private-value") })
    }

    func testReportKeepsDisplayedReadingSeparateFromFreshBatteryInputs() {
        var snapshot = PowerSnapshot()
        snapshot.percent = 47
        snapshot.plugged = false
        snapshot.batteryW = -12.5
        snapshot.systemW = 12.5
        snapshot.batteryTimeEstimate = .remaining(132)
        let report = FeedbackDiagnostics.makeReport(
            context: FeedbackDiagnostics.Context(
                version: "4.2.0", build: "4.2.0",
                settings: ["liquidGlassStyle": "regular", "theme": "dark"],
                accessibility: ["reduceTransparency": "false"],
                displayedSnapshot: snapshot
            ),
            system: ["macOS": "macOS 26.0", "macModel": "Mac15,7"],
            helper: ["health": "healthy"],
            batteryProperties: ["CurrentCapacity": 48, "MaxCapacity": 100]
        )

        XCTAssertTrue(report.text.contains("version: 4.2.0"))
        XCTAssertTrue(report.text.contains("macModel: Mac15,7"))
        XCTAssertTrue(report.text.contains("liquidGlassStyle: regular"))
        XCTAssertTrue(report.text.contains("reduceTransparency: false"))
        XCTAssertTrue(report.text.contains("health: healthy"))
        XCTAssertTrue(report.text.contains("[Displayed reading (current)]"))
        XCTAssertTrue(report.text.contains("batteryPercent: 47"))
        XCTAssertTrue(report.text.contains("estimatedRuntimeMinutes: 132"))
        XCTAssertTrue(report.text.contains("batteryTimeKind: remaining"))
        XCTAssertTrue(report.text.contains("estimatedTimeToFullMinutes: unavailable"))
        XCTAssertTrue(report.text.contains("[Battery inputs read for this report (raw firmware units)]"))
        XCTAssertTrue(report.text.contains("CurrentCapacity: 48"))
        XCTAssertTrue(report.text.contains("Excludes serial numbers"))
    }

    func testBatteryTimeDiagnosticsDistinguishDirectionAndUnknownValues() {
        for (estimate, kind, runtime, charging): (BatteryTimeEstimate?, String, String, String) in [
            (.remaining(nil), "remaining", "unavailable", "unavailable"),
            (.charging(42), "charging", "unavailable", "42"),
            (.charging(nil), "charging", "unavailable", "unavailable"),
            (.full, "full", "unavailable", "unavailable"),
            (.notCharging, "notCharging", "unavailable", "unavailable"),
            (nil, "unavailable", "unavailable", "unavailable"),
        ] {
            let report = FeedbackDiagnostics.makeReport(
                context: FeedbackDiagnostics.Context(
                    version: "4.3.2", build: "4.3.2", settings: [:], accessibility: [:],
                    displayedSnapshot: PowerSnapshot(batteryTimeEstimate: estimate)
                ),
                system: [:], helper: [:], batteryProperties: nil
            )
            XCTAssertTrue(report.text.contains("batteryTimeKind: \(kind)\n"))
            XCTAssertTrue(report.text.contains("estimatedRuntimeMinutes: \(runtime)\n"))
            XCTAssertTrue(report.text.contains("estimatedTimeToFullMinutes: \(charging)\n"))
        }
    }

    func testStaleDisplayedReadingIsClearlyMarked() {
        let report = FeedbackDiagnostics.makeReport(
            context: FeedbackDiagnostics.Context(
                version: "4.2.0", build: "4.2.0", settings: [:],
                accessibility: [:], displayedSnapshot: PowerSnapshot(),
                displayedReadingIsStale: true
            ),
            system: [:], helper: [:], batteryProperties: nil
        )
        XCTAssertTrue(report.text.contains("[Displayed reading (last known; current telemetry unavailable)]"))
        XCTAssertFalse(report.text.contains("[Displayed reading (current)]"))
    }

    func testUnavailableBatteryDoesNotInventZeroReadings() {
        let report = FeedbackDiagnostics.makeReport(
            context: FeedbackDiagnostics.Context(
                version: "Unknown", build: "Unknown", settings: [:],
                accessibility: [:], displayedSnapshot: nil
            ),
            system: [:], helper: ["health": "not checked (socket absent)"],
            batteryProperties: nil
        )

        XCTAssertTrue(report.text.contains("[Displayed reading]\nunavailable"))
        XCTAssertTrue(report.text.contains("batteryService: unavailable"))
        XCTAssertFalse(report.text.contains("batteryPercent:"))
        XCTAssertFalse(report.text.contains("systemWatts:"))
    }

    func testIssueDraftEncodesEnvironmentAndAsksForReviewedAttachment() throws {
        let version = "4.2 & # ? + 中文"
        let macOS = "macOS 26.0 (Build 25A & test)"
        let url = FeedbackDiagnostics.issueURL(version: version, macOS: macOS)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/laleoarrow/battery-monitor/issues/new")
        XCTAssertNil(components.fragment)
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        XCTAssertEqual(components.queryItems?.count, 1)
        let body = try XCTUnwrap(components.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains("Wattson: \(version)"))
        XCTAssertTrue(body.contains("macOS: \(macOS)"))
        XCTAssertTrue(body.contains("Review and drag Wattson-Diagnostics.txt"))
        XCTAssertTrue(body.contains("issues and attachments are public"))
        XCTAssertFalse(body.contains("/Users/"))
    }
}
