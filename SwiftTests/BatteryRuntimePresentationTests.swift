import AppKit
import XCTest
@testable import Wattson

final class BatteryRuntimePresentationTests: XCTestCase {
    func testFallbackRuntimeShowsApproximationAndExplainsItsSource() throws {
        let runtime = PopoverRuntimeView()
        runtime.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                               height: PopoverRuntimeView.preferredHeight)
        var snapshot = PowerSnapshot(batteryW: -24, systemW: 24,
                                     batteryTimeEstimate: .remaining(180),
                                     batteryTimeEstimateSource: .observedDischarge)
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            runtime.appearance = NSAppearance(named: appearanceName)
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot),
                           "Estimated Battery Runtime · ≈3h 0m")
            XCTAssertTrue(runtime.layoutFitsForTest(snapshot: snapshot))
            XCTAssertTrue(runtime.toolTip?.contains("average discharge current") == true)
            let reading = try XCTUnwrap(runtime.subviews.compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "≈3h 0m" })
            XCTAssertEqual(reading.accessibilityHelp(), runtime.toolTip)
            XCTAssertEqual(reading.alignment, .right)
        }
        snapshot.batteryTimeEstimateSource = .batteryGauge
        XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot),
                       "Estimated Battery Runtime · 3h 0m")
        XCTAssertTrue(runtime.toolTip?.contains("battery controller") == true)
        snapshot.plugged = true
        snapshot.batteryW = 20
        snapshot.batteryTimeEstimate = .charging(19)
        XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot),
                       "Estimated Time to Full · 19m")
        XCTAssertTrue(runtime.toolTip?.contains("until full") == true)
        snapshot.batteryTimeEstimateSource = .observedDischarge
        XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot, degraded: true),
                       "Estimated Time to Full · Unavailable")
    }

    func testRuntimeUsesHoursAndMinutesWithoutLosingOtherHeaderReadings() {
        let header = PopoverHeaderView()
        let runtime = PopoverRuntimeView()
        header.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                              height: PopoverHeaderView.preferredHeight)
        XCTAssertEqual(PopoverHeaderView.preferredHeight, 48)
        for (minutes, text) in [(0, "<1m"), (35, "35m"), (60, "1h 0m"),
                                (265, "4h 25m"), (Int(Int32.max), "35791394h 7m")] {
            let snapshot = PowerSnapshot(percent: 41, batteryW: -12, systemW: 12,
                                         batteryTimeEstimate: .remaining(minutes))
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot),
                           "Estimated Battery Runtime · \(text)")
            XCTAssertEqual(header.statePresentationForTest(snapshot: snapshot).text, "On Battery")
            XCTAssertTrue(header.layoutFitsForTest(snapshot: snapshot))
            XCTAssertTrue(runtime.layoutFitsForTest(snapshot: snapshot))
        }
    }

    func testRuntimeSectionKeepsTheClockBesideItsCaptionAndProminentTime() {
        let runtime = PopoverRuntimeView()
        runtime.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                               height: PopoverRuntimeView.preferredHeight)
        XCTAssertEqual(PopoverRuntimeView.preferredHeight, 88)
        let snapshots: [(PowerSnapshot, CGFloat)] = [
            (PowerSnapshot(percent: 41, batteryW: -12, systemW: 12, batteryTimeEstimate: .remaining(265)), 24),
            (PowerSnapshot(percent: 41, batteryW: -12, systemW: 12, batteryTimeEstimate: .remaining(nil)), 16),
            (PowerSnapshot(percent: 41, batteryW: -12, systemW: 12), 16),
            (PowerSnapshot(percent: 41, batteryW: -12, systemW: 12,
                           batteryTimeEstimate: .remaining(Int(Int32.max))), 24),
            (PowerSnapshot(percent: 41, plugged: true, adapterW: 40, batteryW: 20, systemW: 20,
                           batteryTimeEstimate: .charging(42)), 24),
            (PowerSnapshot(percent: 41, plugged: true, adapterW: 40, batteryW: 20, systemW: 20,
                           batteryTimeEstimate: .charging(nil)), 16),
            (PowerSnapshot(percent: 100, plugged: true, adapterW: 20, batteryW: 0, systemW: 20,
                           batteryTimeEstimate: .full), 16),
            (PowerSnapshot(percent: 80, plugged: true, adapterW: 20, batteryW: 0, systemW: 20,
                           batteryTimeEstimate: .notCharging), 16),
            (PowerSnapshot(percent: 41, plugged: true, adapterW: 20, batteryW: -12, systemW: 32,
                           batteryTimeEstimate: .notCharging), 16),
            (PowerSnapshot(percent: 8, batteryW: -10, systemW: 10, batteryTimeEstimate: .remaining(18)), 24),
            (PowerSnapshot(percent: 41, batteryW: -10, systemW: 10,
                           lowPowerMode: true, batteryTimeEstimate: .remaining(310)), 24),
        ]
        for (snapshot, valueFontSize) in snapshots {
            for degraded in [false, true] {
                XCTAssertTrue(runtime.layoutFitsForTest(snapshot: snapshot, degraded: degraded))
                let layout = runtime.sectionLayoutForTest
                XCTAssertTrue(layout.hasTopSeparator)
                XCTAssertEqual(runtime.layer?.backgroundColor?.alpha ?? 0, 0)
                let filledSurfaces = runtime.layer?.sublayers?.filter {
                    ($0.backgroundColor?.alpha ?? 0) > 0 && $0.frame.height > 1
                } ?? []
                XCTAssertEqual(filledSurfaces.map(\.frame), [layout.iconWellFrame])
                XCTAssertEqual(layout.iconWellFrame, NSRect(x: 12, y: 22, width: 44, height: 44))
                XCTAssertEqual(layout.iconFrame.size, NSSize(width: 24, height: 24))
                XCTAssertEqual(layout.iconFrame.midX, layout.iconWellFrame.midX)
                XCTAssertEqual(layout.iconFrame.midY, layout.iconWellFrame.midY)
                XCTAssertEqual(layout.titleFrame.minX, layout.valueFrame.minX)
                XCTAssertTrue(runtime.subviews.compactMap { $0 as? NSTextField }.allSatisfy { $0.alignment == .right })
                XCTAssertEqual(layout.titleFrame.minX - layout.iconWellFrame.maxX, 12)
                XCTAssertLessThan(layout.titleFrame.maxY, layout.valueFrame.minY)
                XCTAssertEqual(layout.titleFontSize, 11.5)
                XCTAssertGreaterThan(layout.valueFontSize, layout.titleFontSize)
                XCTAssertEqual(runtime.layer?.shadowOpacity, 0)
                XCTAssertTrue(runtime.layer?.sublayers?.allSatisfy { $0.shadowOpacity == 0 } ?? false)
                XCTAssertEqual(layout.valueFontSize, degraded ? 16 : valueFontSize)
                for frame in [layout.titleFrame, layout.valueFrame, layout.iconFrame, layout.iconWellFrame] {
                    XCTAssertTrue(runtime.bounds.contains(frame))
                }
            }
        }
    }

    func testRuntimeSectionFollowsLightDarkChangesWithoutChangingItsReadingOrGeometry() throws {
        try withDisplayFlags(contrast: false, reduceTransparency: false) {
            let runtime = PopoverRuntimeView()
            runtime.update(snapshot: PowerSnapshot(batteryTimeEstimate: .remaining(265)), degraded: false)
            runtime.layoutSubtreeIfNeeded()
            let originalFrames = runtime.subviews.map(\.frame)
            var fills: [NSColor] = []
            for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua] {
                runtime.appearance = try XCTUnwrap(NSAppearance(named: name))
                // Unattached views have no display pass to deliver this callback.
                NSAppearance(named: name == .aqua ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                    runtime.viewDidChangeEffectiveAppearance()
                }
                let colors = runtime.wellColorsForTest
                let appearance = runtime.effectiveAppearance
                try assertColor(colors.fill, matches: PopoverStyle.well, in: appearance)
                try assertColor(colors.border, matches: PopoverStyle.neutral.withAlphaComponent(0.34), in: appearance)
                XCTAssertNil(colors.iconTint)
                let clock = try XCTUnwrap(runtime.subviews.compactMap { $0 as? NSImageView }.first)
                XCTAssertFalse(try XCTUnwrap(clock.image).isTemplate)
                let separator = try XCTUnwrap(runtime.layer?.sublayers?.first { $0.frame.height == 0.5 })
                try assertColor(separator.backgroundColor, matches: PopoverStyle.separator, in: appearance)
                XCTAssertEqual(runtime.layer?.backgroundColor?.alpha ?? 0, 0)
                let reading = try XCTUnwrap(runtime.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "4h 25m" })
                try assertColor(resolved(try XCTUnwrap(reading.textColor), in: appearance), matches: PopoverStyle.primaryText, in: appearance)
                fills.append(try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(colors.fill))?.usingColorSpace(.sRGB)))
                XCTAssertEqual(runtime.presentationForTest, "Estimated Battery Runtime · 4h 25m")
                XCTAssertEqual(runtime.subviews.map(\.frame), originalFrames)
            }
            XCTAssertGreaterThan(fills[0].redComponent, fills[1].redComponent)
            XCTAssertEqual(fills[0], fills[2])
        }
    }

    func testRuntimeSectionAccessibilityChangesRefreshNeutralWellAndSeparatorInTheExistingContent() throws {
        try withDisplayFlags(contrast: false, reduceTransparency: false) {
            try withIsolatedSettings { _ in
                let content = PopoverContentViewController()
                content.setViewportHeight(content.preferredHeight)
                let runtime = try XCTUnwrap(descendants(content.view).compactMap { $0 as? PopoverRuntimeView }.first)
                for name: NSAppearance.Name in [.aqua, .darkAqua] {
                    content.view.appearance = try XCTUnwrap(NSAppearance(named: name))
                    content.view.viewDidChangeEffectiveAppearance()
                    let normalWidth = runtime.wellColorsForTest.borderWidth
                    for contrast in [true, false, true, false] {
                        setenv("WATTSON_FORCE_INCREASE_CONTRAST", contrast ? "1" : "0", 1)
                        NSWorkspace.shared.notificationCenter.post(
                            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                            object: NSWorkspace.shared
                        )
                        let colors = runtime.wellColorsForTest
                        let appearance = runtime.effectiveAppearance
                        try assertColor(colors.border, matches: contrast ? PopoverStyle.wellBorder
                                        : PopoverStyle.neutral.withAlphaComponent(0.34), in: appearance)
                        try assertColor(colors.fill, matches: PopoverStyle.well, in: appearance)
                        let separator = try XCTUnwrap(runtime.layer?.sublayers?.first { $0.frame.height == 0.5 })
                        try assertColor(separator.backgroundColor, matches: PopoverStyle.separator, in: appearance)
                        XCTAssertEqual(runtime.layer?.backgroundColor?.alpha ?? 0, 0)
                        if contrast {
                            XCTAssertGreaterThan(colors.borderWidth, normalWidth)
                        } else {
                            XCTAssertEqual(colors.borderWidth, normalWidth)
                        }
                    }
                    setenv("WATTSON_FORCE_REDUCE_TRANSPARENCY", "1", 1)
                    NSWorkspace.shared.notificationCenter.post(
                        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                        object: NSWorkspace.shared
                    )
                    try assertColor(runtime.wellColorsForTest.fill, matches: PopoverStyle.well, in: runtime.effectiveAppearance)
                    XCTAssertEqual(runtime.layer?.backgroundColor?.alpha ?? 0, 0)
                    setenv("WATTSON_FORCE_REDUCE_TRANSPARENCY", "0", 1)
                }
            }
        }
    }

    func testBatteryTimeSwitchesDirectionAndAccessibleLabelWithoutRebuildingTheView() throws {
        let runtime = PopoverRuntimeView()
        let sequence: [(PowerSnapshot, String, String, CGFloat)] = [
            (PowerSnapshot(batteryW: -12, systemW: 12, batteryTimeEstimate: .remaining(265)),
             "Estimated Battery Runtime", "4h 25m", 24),
            (PowerSnapshot(percent: 72, plugged: true, adapterW: 40, batteryW: 20, systemW: 20,
                           batteryTimeEstimate: .charging(42)),
             "Estimated Time to Full", "42m", 24),
            (PowerSnapshot(percent: 100, plugged: true, adapterW: 20, systemW: 20,
                           batteryTimeEstimate: .full),
             "Estimated Time to Full", "Fully Charged", 16),
            (PowerSnapshot(percent: 80, plugged: true, adapterW: 20, systemW: 20,
                           batteryTimeEstimate: .notCharging),
             "Estimated Time to Full", "Not Charging", 16),
            (PowerSnapshot(batteryW: -12, systemW: 12, batteryTimeEstimate: .remaining(nil)),
             "Estimated Battery Runtime", "Calculating…", 16),
            (PowerSnapshot(batteryW: -12, systemW: 12, batteryTimeEstimate: .remaining(35)),
             "Estimated Battery Runtime", "35m", 24),
        ]
        let originalSubviews = runtime.subviews
        for (snapshot, title, value, fontSize) in sequence {
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot), "\(title) · \(value)")
            XCTAssertTrue(runtime.layoutFitsForTest(snapshot: snapshot))
            XCTAssertEqual(runtime.sectionLayoutForTest.valueFontSize, fontSize)
            let reading = try XCTUnwrap(runtime.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == value })
            XCTAssertEqual(reading.accessibilityLabel(), snapshot.plugged
                ? "Estimated time to full charge" : "Estimated battery runtime")
            let help = try XCTUnwrap(reading.accessibilityHelp())
            if snapshot.batteryTimeEstimate == .full {
                XCTAssertTrue(help.localizedCaseInsensitiveContains("fully charged"))
                XCTAssertFalse(help.contains("while charging"))
                XCTAssertFalse(help.contains("macOS"))
                XCTAssertFalse(help.localizedCaseInsensitiveContains("estimate"))
            } else {
                XCTAssertTrue(help.contains(snapshot.plugged ? "while charging" : "remaining battery time"))
            }
            XCTAssertTrue(zip(runtime.subviews, originalSubviews).allSatisfy { $0 === $1 })
        }
    }

    func testMissingDataUnknownEstimatesAndDegradationNeverReuseOldNumbers() {
        let runtime = PopoverRuntimeView()
        for plugged in [false, true] {
            let title = plugged ? "Estimated Time to Full" : "Estimated Battery Runtime"
            let known = PowerSnapshot(plugged: plugged, batteryW: plugged ? 12 : -12,
                                      batteryTimeEstimate: plugged ? .charging(42) : .remaining(265))
            _ = runtime.runtimePresentationForTest(snapshot: known)
            var snapshot = known
            snapshot.batteryTimeEstimate = plugged ? .charging(nil) : .remaining(nil)
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot), "\(title) · Calculating…")
            snapshot.batteryTimeEstimate = nil
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot), "\(title) · Unavailable")
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: known, degraded: true), "\(title) · Unavailable")
        }
    }

    func testBatteryTimeRejectsEstimatesFromTheOppositePowerSource() {
        let runtime = PopoverRuntimeView()
        for estimate: BatteryTimeEstimate in [.charging(42), .charging(nil), .full, .notCharging] {
            let snapshot = PowerSnapshot(batteryW: -12, systemW: 12, batteryTimeEstimate: estimate)
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot),
                           "Estimated Battery Runtime · Unavailable")
        }
        for estimate: BatteryTimeEstimate in [.remaining(265), .remaining(nil)] {
            let snapshot = PowerSnapshot(percent: 72, plugged: true, adapterW: 40,
                                         batteryW: 20, systemW: 20, batteryTimeEstimate: estimate)
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot),
                           "Estimated Time to Full · Unavailable")
        }
    }

    func testMixedSupplyNeverShowsATimeToFull() {
        let runtime = PopoverRuntimeView()
        for estimate: BatteryTimeEstimate in [.charging(42), .charging(nil), .full, .notCharging] {
            let snapshot = PowerSnapshot(percent: 72, plugged: true, adapterW: 20,
                                         batteryW: -12, systemW: 32, batteryTimeEstimate: estimate)
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot),
                           "Estimated Time to Full · Not Charging")
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot, degraded: true),
                           "Estimated Time to Full · Unavailable")
        }
    }

    func testLowBatteryAndLowPowerKeepTheMacOSEstimate() {
        let runtime = PopoverRuntimeView()
        for lowPower in [false, true] {
            let snapshot = PowerSnapshot(percent: 8, batteryW: -10, systemW: 10,
                                         lowPowerMode: lowPower, batteryTimeEstimate: .remaining(18))
            XCTAssertEqual(runtime.runtimePresentationForTest(snapshot: snapshot),
                           "Estimated Battery Runtime · 18m")
        }
    }

    func testRuntimeMenuChoiceRemovesExactlyItsOwnHeightAndPersists() {
        withIsolatedSettings { defaults in
            let content = PopoverContentViewController()
            _ = content.view
            let defaultHeight = content.preferredHeight
            XCTAssertFalse(content.moduleIsHiddenForTest(.runtime))

            content.toggleModuleFromMenuForTest(.runtime)

            XCTAssertFalse(Settings.isModuleVisible(.runtime))
            XCTAssertEqual(defaults.object(forKey: Settings.Module.runtime.defaultsKey) as? Bool, false)
            XCTAssertTrue(content.moduleIsHiddenForTest(.runtime))
            XCTAssertEqual(content.preferredHeight, defaultHeight - PopoverRuntimeView.preferredHeight)
            for module in [PopoverModule.flow, .ring, .lanes, .history] {
                XCTAssertFalse(content.moduleIsHiddenForTest(module))
            }
            let reopened = PopoverContentViewController()
            _ = reopened.view
            XCTAssertTrue(reopened.moduleIsHiddenForTest(.runtime))
            XCTAssertEqual(reopened.preferredHeight, defaultHeight - PopoverRuntimeView.preferredHeight)

            content.toggleModuleFromMenuForTest(.runtime)
            XCTAssertEqual(content.preferredHeight, defaultHeight)
            XCTAssertFalse(reopened.moduleIsHiddenForTest(.runtime))
        }
    }

    func testHiddenRuntimeSkipsRenderingAndShowsNewestCachedDirectionAndState() {
        withIsolatedSettings { _ in
            let content = PopoverContentViewController()
            _ = content.view
            content.setPresentationActive(true)
            content.update(snapshot: PowerSnapshot(batteryTimeEstimate: .remaining(265)),
                           history: [], peak: 0, degraded: false)
            XCTAssertEqual(content.runtimePresentationForTest, "Estimated Battery Runtime · 4h 25m")
            Settings.setModule(.runtime, visible: false)
            let before = content.moduleUpdateCountsForTest[.runtime, default: 0]

            content.update(snapshot: PowerSnapshot(plugged: true, batteryW: 12,
                                                   batteryTimeEstimate: .charging(42)),
                           history: [], peak: 0, degraded: false)
            XCTAssertEqual(content.moduleUpdateCountsForTest[.runtime, default: 0], before)
            XCTAssertEqual(content.runtimePresentationForTest, "Estimated Battery Runtime · 4h 25m")

            Settings.setModule(.runtime, visible: true)
            XCTAssertEqual(content.moduleUpdateCountsForTest[.runtime, default: 0], before + 1)
            XCTAssertEqual(content.runtimePresentationForTest, "Estimated Time to Full · 42m")
            Settings.setModule(.runtime, visible: false)
            content.update(snapshot: PowerSnapshot(percent: 100, plugged: true, batteryTimeEstimate: .full),
                           history: [], peak: 0, degraded: false)
            Settings.setModule(.runtime, visible: true)
            XCTAssertEqual(content.runtimePresentationForTest, "Estimated Time to Full · Fully Charged")
            Settings.setModule(.runtime, visible: false)
            content.update(snapshot: PowerSnapshot(batteryTimeEstimate: .remaining(35)),
                           history: [], peak: 0, degraded: true)
            Settings.setModule(.runtime, visible: true)
            XCTAssertEqual(content.runtimePresentationForTest, "Estimated Battery Runtime · Unavailable")
            content.update(snapshot: PowerSnapshot(batteryTimeEstimate: .remaining(35)),
                           history: [], peak: 0, degraded: false)
            XCTAssertEqual(content.runtimePresentationForTest, "Estimated Battery Runtime · 35m")
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func resolved(_ color: NSColor, in appearance: NSAppearance) -> CGColor {
        var result = NSColor.clear.cgColor
        appearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    private func assertColor(_ actual: CGColor?, matches expected: NSColor, in appearance: NSAppearance,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(actual))?.usingColorSpace(.sRGB))
        let expected = try XCTUnwrap(NSColor(cgColor: resolved(expected, in: appearance))?.usingColorSpace(.sRGB))
        for (actual, expected) in zip([actual.redComponent, actual.greenComponent, actual.blueComponent, actual.alphaComponent],
                                      [expected.redComponent, expected.greenComponent, expected.blueComponent, expected.alphaComponent]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001, file: file, line: line)
        }
    }

    private func withDisplayFlags(contrast: Bool, reduceTransparency: Bool, _ body: () throws -> Void) rethrows {
        let flags = ["WATTSON_FORCE_INCREASE_CONTRAST": contrast,
                     "WATTSON_FORCE_REDUCE_TRANSPARENCY": reduceTransparency]
        let prior = flags.keys.map { ($0, ProcessInfo.processInfo.environment[$0]) }
        for (key, value) in flags { setenv(key, value ? "1" : "0", 1) }
        defer {
            for (key, value) in prior {
                if let value { setenv(key, value, 1) } else { unsetenv(key) }
            }
        }
        try body()
    }

    private func withIsolatedSettings(_ body: (UserDefaults) throws -> Void) rethrows {
        let runID = ProcessInfo.processInfo.environment["WATTSON_RUNTIME_TEST_RUN_ID"]
            .flatMap(UUID.init(uuidString:)) ?? UUID()
        let suiteName = registerTestDefaultsSuite("Wattson.SwiftTests.RuntimeModule.\(runID.uuidString)")
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentTestDomain(forName: suiteName)
        }
        try body(defaults)
    }
}
