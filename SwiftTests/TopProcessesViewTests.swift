import AppKit
import Darwin
import XCTest
@testable import Wattson

final class TopProcessesViewTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "Wattson.SwiftTests.TopProcesses.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testIdenticalUpdatesSkipContentWorkAfterInitializingEveryStatus() throws {
        let view = makeView()
        XCTAssertEqual(view.contentUpdatesForTest, 0)
        for (index, state) in [TopProcessesState.loading, .unavailable, .ready([]), .ready(processes(3))].enumerated() {
            view.update(state: state, count: 3)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.contentUpdatesForTest, index + 1)
            let status = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.last)
            XCTAssertEqual(status.toolTip, ["Sampling activity…", "Requires the Wattson helper", nil, nil][index])
            XCTAssertFalse(status.accessibilityHelp()?.isEmpty ?? true)
            let rows = visibleRows(view)
            let fields = rows.flatMap { $0.subviews.compactMap { $0 as? NSTextField } }
            let text = fields.map(\.stringValue)
            let tips = rows.map(\.toolTip)
            let accessibility = rows.map { $0.accessibilityValue() as? String }
            for _ in 0..<100 {
                view.update(state: state, count: 3)
            }
            XCTAssertEqual(view.contentUpdatesForTest, index + 1)
            XCTAssertFalse(view.needsLayout)
            XCTAssertEqual(visibleRows(view).map(ObjectIdentifier.init), rows.map(ObjectIdentifier.init))
            XCTAssertEqual(fields.map(\.stringValue), text)
            XCTAssertEqual(rows.map(\.toolTip), tips)
            XCTAssertEqual(rows.map { $0.accessibilityValue() as? String }, accessibility)
        }
    }

    func testNormalizedCountAndCompactChangesInvalidateContentOnlyWhenTheirValuesChange() {
        let view = makeView(count: 10)
        let state = TopProcessesState.ready(processes(10))
        for count in [0, 1, -20] {
            view.update(state: state, count: count)
            XCTAssertEqual(view.contentUpdatesForTest, 1)
            XCTAssertEqual(visibleRows(view).count, 1)
        }
        for count in [10, 11, Int.max] {
            view.update(state: state, count: count)
            XCTAssertEqual(view.contentUpdatesForTest, 2)
            XCTAssertEqual(visibleRows(view).count, 10)
        }
        for (index, compact) in [true, false, true].enumerated() {
            view.frame.size.height = TopProcessesView.preferredHeight(count: 10, compact: compact)
            view.update(state: state, count: 10, compact: compact)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.contentUpdatesForTest, index + 3)
            XCTAssertEqual(visibleRows(view).map { $0.frame.height }, Array(repeating: compact ? 28 : 44, count: 10))
            for row in visibleRows(view) {
                XCTAssertEqual(row.subviews.compactMap { $0 as? NSTextField }[2].isHidden, compact)
            }
            for _ in 0..<100 { view.update(state: state, count: 100, compact: compact) }
            XCTAssertEqual(view.contentUpdatesForTest, index + 3)
            XCTAssertFalse(view.needsLayout)
        }
    }

    func testEveryProcessFieldRankAndUnshownReadingInvalidatesContent() throws {
        let view = makeView(count: 1)
        let original = EnergyProcess(pid: 42, name: "Worker", energyImpact: 84,
                                     cpuPercent: 72, idleWakeupsPerSecond: 240)
        let variants = [
            EnergyProcess(pid: 43, name: "Worker", energyImpact: 84, cpuPercent: 72, idleWakeupsPerSecond: 240),
            EnergyProcess(pid: 42, name: "Renamed", energyImpact: 84, cpuPercent: 72, idleWakeupsPerSecond: 240),
            EnergyProcess(pid: 42, name: "Worker", energyImpact: 84.01, cpuPercent: 72, idleWakeupsPerSecond: 240),
            EnergyProcess(pid: 42, name: "Worker", energyImpact: 84, cpuPercent: 72.01, idleWakeupsPerSecond: 240),
            EnergyProcess(pid: 42, name: "Worker", energyImpact: 84, cpuPercent: 72, idleWakeupsPerSecond: 240.01),
        ]
        let second = process(99, score: 20)
        view.update(state: .ready([original, second]), count: 1)
        for reading in variants {
            view.update(state: .ready([original, second]), count: 1)
            let updates = view.contentUpdatesForTest
            view.update(state: .ready([reading, second]), count: 1)
            XCTAssertEqual(view.contentUpdatesForTest, updates + 1)
            let row = try XCTUnwrap(visibleRows(view).first)
            let fields = row.subviews.compactMap { $0 as? NSTextField }
            let summary = "Score 84.0 · CPU 72.0% · Wakeups 240/s"
            XCTAssertEqual(fields[0].stringValue, reading.name)
            XCTAssertEqual(fields[0].toolTip, "\(reading.name) · PID \(reading.pid)")
            XCTAssertEqual(fields[1].toolTip, summary)
            XCTAssertEqual(fields[2].toolTip, summary)
            XCTAssertEqual(row.accessibilityLabel(), reading.name)
            XCTAssertEqual(row.accessibilityValue() as? String, "Activity Score 84.0; CPU 72.0%; idle wakeups 240 per second")
            XCTAssertEqual(row.toolTip, "\(reading.name) · PID \(reading.pid)\n\(summary)")
        }
        let updates = view.contentUpdatesForTest
        view.update(state: .ready([second, variants.last!]), count: 1)
        XCTAssertEqual(view.contentUpdatesForTest, updates + 1)
        XCTAssertEqual(try XCTUnwrap(visibleRows(view).first).accessibilityLabel(), second.name)
        view.update(state: .ready([second, original]), count: 1)
        XCTAssertEqual(view.contentUpdatesForTest, updates + 2)
        view.update(state: .ready([second]), count: 1)
        XCTAssertEqual(view.contentUpdatesForTest, updates + 3)
    }

    func testIdenticalDataDoesNotBlockExternalLayoutOrAppearanceRefresh() throws {
        let view = makeView()
        let state = TopProcessesState.ready(processes(3))
        view.update(state: state, count: 3)
        view.layoutSubtreeIfNeeded()
        let updates = view.contentUpdatesForTest
        let rows = visibleRows(view)
        let oldWidth = view.bounds.width
        view.frame.size.width += 40
        view.needsLayout = true
        view.update(state: state, count: 3)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.contentUpdatesForTest, updates)
        XCTAssertTrue(rows.allSatisfy { $0.frame.width == oldWidth + 40 })
        XCTAssertTrue(rows.allSatisfy { $0.subviews.compactMap { $0 as? NSTextField }[2].frame.width == oldWidth + 40 })

        let originalContrast = ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"]
        defer {
            if let originalContrast { setenv("WATTSON_FORCE_INCREASE_CONTRAST", originalContrast, 1) }
            else { unsetenv("WATTSON_FORCE_INCREASE_CONTRAST") }
        }
        for (appearanceName, contrast): (NSAppearance.Name, Bool) in [(.accessibilityHighContrastDarkAqua, true), (.aqua, false)] {
            setenv("WATTSON_FORCE_INCREASE_CONTRAST", contrast ? "1" : "0", 1)
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            view.appearance = appearance
            view.refreshAppearance()
            view.update(state: state, count: 3)
            XCTAssertEqual(view.contentUpdatesForTest, updates)
            for row in rows {
                try assertPalette(row, follows: PopoverStyle.blue, in: appearance, contrast: contrast)
            }
        }
        view.setPresentationActive(false)
        view.update(state: state, count: 3)
        XCTAssertEqual(view.contentUpdatesForTest, updates)
        XCTAssertNil(view.helpWindow)
    }

    func testConfiguredHeightAndVisibleGeometryStayStableAcrossStates() {
        XCTAssertEqual(TopProcessesView.preferredHeight(count: 3), 168)
        for count in [1, 3, 10] {
            let view = makeView(count: count)
            let originalHeight = view.frame.height
            for state: TopProcessesState in [.loading, .unavailable, .ready([]), .ready(processes(count))] {
                view.update(state: state, count: count)
                view.layoutSubtreeIfNeeded()
                XCTAssertEqual(view.frame.height, originalHeight)
                XCTAssertEqual(view.layer?.backgroundColor?.alpha ?? 0, 0)
                XCTAssertEqual(view.layer?.shadowOpacity, 0)
                XCTAssertTrue(view.layer?.sublayers?.contains {
                    $0.frame == NSRect(x: 0, y: 0, width: view.bounds.width, height: 0.5)
                } == true)
                XCTAssertTrue(view.subviews.filter { !$0.isHidden }.allSatisfy { view.bounds.contains($0.frame) })
                for row in visibleRows(view) {
                    XCTAssertTrue(row.subviews.allSatisfy { row.bounds.contains($0.frame) })
                }
            }
        }
        XCTAssertEqual(TopProcessesView.preferredHeight(count: 0), TopProcessesView.preferredHeight(count: 1))
        XCTAssertEqual(TopProcessesView.preferredHeight(count: 99), TopProcessesView.preferredHeight(count: 10))
    }

    func testCompactHeightAndVisibleGeometryFitConfiguredCountsAcrossStates() {
        XCTAssertEqual(TopProcessesView.preferredHeight(count: 3, compact: true), 120)
        for count in [1, 3, 10] {
            let view = makeView(count: count, compact: true)
            for state: TopProcessesState in [.loading, .unavailable, .ready([]), .ready(processes(count))] {
                view.update(state: state, count: count, compact: true)
                view.layoutSubtreeIfNeeded()
                XCTAssertEqual(view.frame.height, 36 + 28 * CGFloat(count))
                XCTAssertTrue(view.subviews.filter { !$0.isHidden }.allSatisfy { view.bounds.contains($0.frame) })
                for row in visibleRows(view) {
                    XCTAssertEqual(row.frame.height, 28)
                    XCTAssertTrue(row.subviews.allSatisfy { row.bounds.contains($0.frame) })
                    let details = row.subviews.compactMap { $0 as? NSTextField }[2]
                    XCTAssertTrue(details.isHidden)
                    XCTAssertEqual(details.frame, .zero)
                }
            }
        }
        XCTAssertEqual(TopProcessesView.preferredHeight(count: 0, compact: true),
                       TopProcessesView.preferredHeight(count: 1, compact: true))
        XCTAssertEqual(TopProcessesView.preferredHeight(count: 99, compact: true),
                       TopProcessesView.preferredHeight(count: 10, compact: true))
    }

    func testCompactToggleReusesRowsAndPreservesValuesGradientAndAccessibleDetails() throws {
        let view = makeView()
        let readings = [0.0, 0.04, 125].enumerated().map { process($0.offset + 1, score: $0.element) }
        view.update(state: .ready(readings), count: 3)
        view.layoutSubtreeIfNeeded()
        let rows = visibleRows(view)
        let fields = rows.flatMap { $0.subviews }.map(ObjectIdentifier.init)
        let accessibility = rows.map { $0.accessibilityValue() as? String }
        let tips = rows.map(\.toolTip)
        for compact in [true, false, true, false] {
            view.frame.size.height = TopProcessesView.preferredHeight(count: 3, compact: compact)
            view.update(state: .ready(readings), count: 3, compact: compact)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(visibleRows(view).map(ObjectIdentifier.init), rows.map(ObjectIdentifier.init))
            XCTAssertEqual(rows.flatMap { $0.subviews }.map(ObjectIdentifier.init), fields)
            XCTAssertEqual(rows.map { $0.accessibilityValue() as? String }, accessibility)
            XCTAssertEqual(rows.map(\.toolTip), tips)
            XCTAssertEqual(rows.map { $0.frame.height }, Array(repeating: compact ? 28 : 44, count: 3))
            for (index, row) in rows.enumerated() {
                let labels = row.subviews.compactMap { $0 as? NSTextField }
                XCTAssertEqual(labels[1].stringValue, ["0.0", "<0.1", "125.0"][index])
                XCTAssertEqual(labels[2].isHidden, compact)
                XCTAssertFalse(labels[2].stringValue.isEmpty)
                XCTAssertTrue(row.toolTip?.contains("CPU") == true)
                XCTAssertTrue((row.accessibilityValue() as? String)?.contains("idle wakeups") == true)
                XCTAssertTrue(row.subviews.allSatisfy { row.bounds.contains($0.frame) })
                let gradient = try gradientLayer(row)
                XCTAssertEqual(gradient.frame.width, 114)
                XCTAssertEqual(try XCTUnwrap(gradient.mask).frame.width, [0, 0.0456, 114][index], accuracy: 0.000_001)
                let overflow = try XCTUnwrap(row.subviews.compactMap { $0 as? NSImageView }.first)
                XCTAssertEqual(overflow.isHidden, index != 2)
            }
        }
    }

    func testMeasuringEmptyAndUnavailableRemainDistinctAndAccessible() throws {
        let view = makeView()
        for (state, text, help): (TopProcessesState, String, String) in [
            (.loading, "Measuring…", "one second"),
            (.unavailable, "Unavailable", "Wattson helper"),
            (.ready([]), "No active processes", "No active process"),
        ] {
            view.update(state: state, count: 3)
            let status = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }
                .first { !$0.isHidden && $0.stringValue == text })
            XCTAssertTrue(status.accessibilityHelp()?.contains(help) == true)
            XCTAssertTrue(visibleRows(view).isEmpty)
        }
        view.update(state: .ready(processes(1)), count: 3)
        XCTAssertEqual(visibleRows(view).count, 1)
        XCTAssertEqual(view.frame.height, 168)
        view.update(state: .ready(processes(12)), count: 100)
        XCTAssertEqual(visibleRows(view).count, 10)
    }

    func testBarsUseFixedHundredPointScaleIndependentOfOtherRowsAndDisplayCount() throws {
        let view = makeView(count: 10)
        let readings = [25.0, 50, 0, 500].enumerated().map {
            process($0.offset + 1, score: $0.element)
        }
        for count in [1, 3, 10, 3] {
            view.update(state: .ready(readings), count: count)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.barGeometryForTest.map(\.ratio), Array([0.25, 0.5, 0, 1].prefix(count)))
            for bar in view.barGeometryForTest {
                XCTAssertEqual(bar.track, NSRect(x: 144, y: 6, width: 116, height: 12))
                XCTAssertEqual(bar.fill.origin, NSPoint(x: 1, y: 1))
                XCTAssertEqual(bar.fill.height, 10)
                XCTAssertEqual(bar.fill.width, 114)
            }
            for (geometry, bar) in zip(view.gradientPreviewGeometryForTest, view.barGeometryForTest) {
                XCTAssertEqual(geometry.visibleMaskWidth, 114 * bar.ratio, accuracy: 0.001)
                XCTAssertTrue(geometry.usesFixedScale)
            }
        }
        let fields = view.subviews.compactMap { $0 as? NSTextField }
        XCTAssertTrue(fields.contains { $0.stringValue == "Process Activity" })
        let scoreHeader = try XCTUnwrap(fields.first { $0.stringValue == "Activity Score" })
        let headerWidth = scoreHeader.stringValue.size(withAttributes: [.font: try XCTUnwrap(scoreHeader.font)]).width
        XCTAssertLessThanOrEqual(headerWidth, scoreHeader.frame.width - 4)
    }

    func testZeroTinyOverflowAndHugeFiniteValuesRemainDistinctAndFit() throws {
        let view = makeView(count: 10)
        let scores = [0.0, 0.04, 100, 100.01, 125.5, 999.94, 999.96, 9_999, 9_999.96, Double.greatestFiniteMagnitude]
        view.update(state: .ready(scores.enumerated().map { process($0.offset + 1, score: $0.element) }), count: 10)
        view.layoutSubtreeIfNeeded()
        let rows = visibleRows(view)
        let values = rows.map { $0.subviews.compactMap { $0 as? NSTextField }[1] }
        XCTAssertEqual(values.map(\.stringValue), ["0.0", "<0.1", "100.0", "100.0", "125.5", "999.9", "1000", "9999", "10000", "2e308"])
        XCTAssertEqual(view.barGeometryForTest.map(\.ratio), [0, 0.0004, 1, 1, 1, 1, 1, 1, 1, 1])
        XCTAssertEqual(view.gradientPreviewGeometryForTest[0].visibleMaskWidth, 0)
        XCTAssertEqual(view.gradientPreviewGeometryForTest[1].visibleMaskWidth, 0.0456, accuracy: 0.000_001)
        XCTAssertTrue(view.gradientPreviewGeometryForTest.allSatisfy { $0.gradientWidth == 114 && $0.usesFixedScale })
        for (index, score) in scores.enumerated() {
            let field = values[index]
            XCTAssertEqual(field.alignment, .right)
            XCTAssertEqual(field.font, PopoverStyle.mono(13, .semibold))
            let textWidth = field.stringValue.size(withAttributes: [.font: try XCTUnwrap(field.font)]).width
            XCTAssertLessThanOrEqual(textWidth, field.frame.width - 4)
            XCTAssertTrue(field.toolTip?.hasPrefix("Score \(field.stringValue) ·") == true)
            let marker = try XCTUnwrap(rows[index].subviews.compactMap { $0 as? NSImageView }
                .first { $0.identifier?.rawValue == "top-processes.overflow" })
            XCTAssertEqual(marker.isHidden, score <= 100)
            XCTAssertEqual(marker.frame, NSRect(x: 262, y: 6, width: 8, height: 12))
            XCTAssertGreaterThan(marker.frame.minX, view.barGeometryForTest[index].track.maxX)
            XCTAssertLessThan(marker.frame.maxX, field.frame.minX)
            XCTAssertFalse(marker.isAccessibilityElement())
            XCTAssertNotNil(marker.image)
        }
        XCTAssertTrue((rows.last?.accessibilityValue() as? String)?.hasPrefix("Activity Score 2e308;") == true)
    }

    func testLongNamesTruncateAndCPUWakeupBreakdownUsesActualInputs() throws {
        let view = makeView(count: 1)
        let longName = String(repeating: "Very Long Process Name ", count: 12)
        let reading = EnergyProcess(pid: 42, name: longName, energyImpact: 84,
                                    cpuPercent: 72, idleWakeupsPerSecond: 240)
        view.update(state: .ready([reading]), count: 1)
        view.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(visibleRows(view).first)
        let fields = row.subviews.compactMap { $0 as? NSTextField }
        XCTAssertEqual(fields.count, 3)
        let name = fields[0]
        XCTAssertEqual(name.font?.pointSize, 13)
        XCTAssertEqual(name.maximumNumberOfLines, 1)
        XCTAssertEqual(name.lineBreakMode, .byTruncatingTail)
        XCTAssertEqual(name.frame, NSRect(x: 0, y: 2, width: 132, height: 20))
        XCTAssertEqual(name.toolTip, "\(longName) · PID 42")
        XCTAssertEqual(fields[1].frame, NSRect(x: 272, y: 2, width: 56, height: 20))
        XCTAssertEqual(fields[1].stringValue, "84.0")
        XCTAssertEqual(fields[2].stringValue, "CPU 72.0% · Idle wakeups 240/s")
        XCTAssertEqual(fields[2].font?.pointSize, 11)
        XCTAssertLessThanOrEqual(fields[2].stringValue.size(withAttributes: [.font: fields[2].font!]).width,
                                 fields[2].frame.width)
        XCTAssertEqual(row.accessibilityLabel(), longName)
        XCTAssertTrue((row.accessibilityValue() as? String)?.contains("CPU 72.0%; idle wakeups 240 per second") == true)
        XCTAssertEqual(row.accessibilityHelp(), "Select to show Force Quit.")
        XCTAssertTrue(row.subviews.allSatisfy { !$0.isAccessibilityElement() })
        let images = row.subviews.compactMap { $0 as? NSImageView }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.identifier?.rawValue, "top-processes.overflow")
        XCTAssertTrue(images.first?.isHidden == true)
    }

    func testChangingMeasurementsOrRankReusesRowsAndChangesWidthAndValueWithoutChangingPalette() throws {
        let view = makeView()
        let original = processes(3)
        view.update(state: .ready(original), count: 3, color: PopoverStyle.green)
        view.layoutSubtreeIfNeeded()
        let rows = visibleRows(view)
        let fields = rows.flatMap { $0.subviews }.map(ObjectIdentifier.init)
        let originalColors = try gradientColors(try XCTUnwrap(rows.first))
        let masks = try rows.map { ObjectIdentifier(try XCTUnwrap(gradientLayer($0).mask)) }
        for iteration in 0..<50 {
            let score = Double(iteration.isMultiple(of: 2) ? iteration : 100 - iteration)
            let order = iteration.isMultiple(of: 2) ? original : Array(original.reversed())
            let updated = order.map {
                EnergyProcess(pid: $0.pid, name: $0.name, energyImpact: score,
                              cpuPercent: score, idleWakeupsPerSecond: 0)
            }
            view.update(state: .ready(updated), count: 3, color: PopoverStyle.green)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(try rows.map { ObjectIdentifier(try XCTUnwrap(gradientLayer($0).mask)) }, masks)
            for geometry in view.gradientPreviewGeometryForTest {
                XCTAssertEqual(geometry.gradientWidth, 114)
                XCTAssertEqual(geometry.visibleMaskWidth, 114 * score / 100, accuracy: 0.000_001)
                XCTAssertTrue(geometry.usesFixedScale)
            }
            XCTAssertEqual(rows.map { $0.subviews.compactMap { $0 as? NSTextField }[0].stringValue }, updated.map(\.name))
        }
        XCTAssertEqual(visibleRows(view).map(ObjectIdentifier.init), rows.map(ObjectIdentifier.init))
        XCTAssertEqual(visibleRows(view).flatMap { $0.subviews }.map(ObjectIdentifier.init), fields)
        let updatedColors = try gradientColors(try XCTUnwrap(rows.first))
        XCTAssertEqual(updatedColors, originalColors)
        XCTAssertEqual(view.barGeometryForTest.map(\.ratio), [0.51, 0.51, 0.51])
        for row in visibleRows(view) {
            let value = try XCTUnwrap(row.subviews.compactMap { $0 as? NSTextField }.dropFirst().first)
            XCTAssertEqual(value.stringValue, "51.0")
            XCTAssertEqual(try gradientColors(row), originalColors)
            try assertPalette(row, follows: PopoverStyle.green, in: view.effectiveAppearance, contrast: false)
        }
    }

    func testAppPaletteChangesImmediatelyWithoutChangingReadingsSelectionOrFixedScale() throws {
        for compact in [false, true] {
            let view = makeView(compact: compact)
            view.appearance = NSAppearance(named: .aqua)
            let readings = [8.1, 46, 131.2].enumerated().map { identifiedProcess($0.offset + 41, score: $0.element) }
            let state = TopProcessesState.ready(readings)
            view.update(state: state, count: 3, compact: compact, color: PopoverStyle.blue)
            view.layoutSubtreeIfNeeded()
            let rows = view.processRowsForTest
            try clickRow(rows[1], point: NSPoint(x: 40, y: 11))
            view.layoutSubtreeIfNeeded()
            let rowIDs = rows.map(ObjectIdentifier.init)
            let labels = rows.map { $0.subviews.compactMap { $0 as? NSTextField } }
            let values = labels.flatMap { $0.map(\.stringValue) }
            let labelFrames = labels.flatMap { $0.map(\.frame) }
            let accessibility = rows.map { $0.accessibilityValue() as? String }
            let maskIDs = try rows.map { ObjectIdentifier(try XCTUnwrap(gradientLayer($0).mask)) }
            let updates = view.contentUpdatesForTest
            var previousPalette = try gradientColors(rows[0])

            for color in [PopoverStyle.green, PopoverStyle.blue, PopoverStyle.neutral, PopoverStyle.green] {
                view.update(state: state, count: 3, compact: compact, color: color)
                XCTAssertEqual(view.contentUpdatesForTest, updates)
                XCTAssertFalse(view.needsLayout)
                XCTAssertEqual(view.processRowsForTest.map(ObjectIdentifier.init), rowIDs)
                XCTAssertEqual(labels.flatMap { $0.map(\.stringValue) }, values)
                XCTAssertEqual(labels.flatMap { $0.map(\.frame) }, labelFrames)
                XCTAssertEqual(rows.map { $0.accessibilityValue() as? String }, accessibility)
                XCTAssertEqual(view.selectedProcessForTest, readings[1])
                XCTAssertEqual(view.selectedRowIndexForTest, 1)
                XCTAssertEqual(view.forceQuitButtonsForTest.map(\.isHidden), [true, false, true])
                XCTAssertEqual(view.forceQuitButtonsForTest[1].frame, NSRect(x: 288, y: 4, width: 38, height: 16))
                XCTAssertEqual(try rows.map { ObjectIdentifier(try XCTUnwrap(gradientLayer($0).mask)) }, maskIDs)
                for (bar, ratio) in zip(view.barGeometryForTest, [0.081, 0.46, 1.0]) {
                    XCTAssertEqual(bar.ratio, ratio, accuracy: 0.000_001)
                }
                for (geometry, ratio) in zip(view.gradientPreviewGeometryForTest, [0.081, 0.46, 1.0]) {
                    XCTAssertEqual(geometry.gradientWidth, 114)
                    XCTAssertEqual(geometry.visibleMaskWidth, 114 * ratio, accuracy: 0.000_001)
                    XCTAssertTrue(geometry.usesFixedScale)
                }
                for row in rows {
                    try assertPalette(row, follows: color, in: view.effectiveAppearance, contrast: false)
                }
                let palette = try gradientColors(rows[0])
                try assertColor(view.forceQuitFeedbackForTest.glowForTest.shadowColor,
                                matches: try sRGBColor(try XCTUnwrap(palette.last)),
                                in: view.effectiveAppearance)
                XCTAssertNotEqual(palette, previousPalette)
                previousPalette = palette
                // A repeated palette update should not rebuild content or schedule layout either.
                view.update(state: state, count: 3, compact: compact, color: color)
                XCTAssertEqual(view.contentUpdatesForTest, updates)
                XCTAssertFalse(view.needsLayout)
                XCTAssertEqual(try gradientColors(rows[0]), palette)
            }
        }
    }

    func testDefaultBarsUseTheSameFixedHorizontalGradientAndRevealOnlyTheMeasuredPrefix() throws {
        let view = makeView()
        view.appearance = NSAppearance(named: .aqua)
        view.update(state: .ready([8.1, 46, 84].enumerated().map {
            process($0.offset + 1, score: $0.element)
        }), count: 3)
        let rows = visibleRows(view)
        let colors = try rows.map { try gradientColors($0).map {
            try XCTUnwrap(NSColor(cgColor: $0)?.usingColorSpace(.sRGB))
        } }
        func brightness(_ color: NSColor) -> CGFloat {
            0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        }
        for stops in colors {
            for color in stops {
                XCTAssertGreaterThan(color.blueComponent, color.greenComponent)
                XCTAssertGreaterThan(color.greenComponent, color.redComponent)
                XCTAssertTrue((0.53...0.65).contains(color.hueComponent))
            }
            XCTAssertGreaterThan(brightness(stops[0]), brightness(stops[1]))
            XCTAssertGreaterThan(brightness(stops[1]), brightness(stops[2]))
        }
        for row in rows {
            let gradient = try gradientLayer(row)
            XCTAssertEqual(gradient.startPoint, CGPoint(x: 0, y: 0.5))
            XCTAssertEqual(gradient.endPoint, CGPoint(x: 1, y: 0.5))
            XCTAssertEqual(gradient.locations, [0, 0.45, 1])
            try assertPalette(row, follows: PopoverStyle.blue, in: view.effectiveAppearance, contrast: false)
            XCTAssertEqual(try gradientColors(row), try gradientColors(rows[0]))
        }
        for (bar, expected) in zip(view.barGeometryForTest, [0.081, 0.46, 0.84]) {
            XCTAssertEqual(bar.ratio, expected, accuracy: 0.000_001)
        }
        // An 8.1-point reading reveals only the pale first 8.1% of the full-scale gradient.
        let shortGradient = try gradientLayer(rows[0])
        XCTAssertEqual(shortGradient.frame.width, 114)
        XCTAssertEqual(try XCTUnwrap(shortGradient.mask).frame.width, 114 * 0.081, accuracy: 0.000_001)
    }

    func testGradientAndOutlineFollowLightDarkAndHighContrastWithoutAnimations() throws {
        let view = makeView()
        let state = TopProcessesState.ready([8.1, 46, 84].enumerated().map {
            process($0.offset + 1, score: $0.element)
        })
        view.update(state: state, count: 3)
        view.layoutSubtreeIfNeeded()
        let frames = view.subviews.map(\.frame)
        let originalContrast = ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"]
        defer {
            if let originalContrast { setenv("WATTSON_FORCE_INCREASE_CONTRAST", originalContrast, 1) }
            else { unsetenv("WATTSON_FORCE_INCREASE_CONTRAST") }
        }
        for appColor in [PopoverStyle.green, PopoverStyle.blue, PopoverStyle.neutral] {
            view.update(state: state, count: 3, color: appColor)
            for (name, contrast): (NSAppearance.Name, Bool) in [(.aqua, false), (.darkAqua, false),
                    (.accessibilityHighContrastAqua, true), (.accessibilityHighContrastDarkAqua, true),
                    (.aqua, false)] {
                setenv("WATTSON_FORCE_INCREASE_CONTRAST", contrast ? "1" : "0", 1)
                let appearance = try XCTUnwrap(NSAppearance(named: name))
                view.appearance = appearance
                view.viewDidChangeEffectiveAppearance()
                view.layoutSubtreeIfNeeded()
                XCTAssertEqual(view.subviews.map(\.frame), frames)
                let separator = try XCTUnwrap(view.layer?.sublayers?.first)
                try assertColor(separator.backgroundColor, matches: PopoverStyle.separator, in: appearance)
                for row in visibleRows(view) {
                    let track = try XCTUnwrap(row.layer?.sublayers?.first { $0.name == "top-processes.track" })
                    let gradient = try XCTUnwrap(track.sublayers?.first as? CAGradientLayer)
                    XCTAssertEqual(gradient.locations, [0, 0.45, 1])
                    XCTAssertEqual(gradient.startPoint, CGPoint(x: 0, y: 0.5))
                    XCTAssertEqual(gradient.endPoint, CGPoint(x: 1, y: 0.5))
                    XCTAssertEqual(track.borderWidth, 1)
                    XCTAssertEqual(track.backgroundColor?.alpha, 0)
                    try assertPalette(row, follows: appColor, in: appearance, contrast: contrast)
                    if contrast {
                        try assertColor(track.borderColor, matches: .labelColor, in: appearance)
                    } else {
                        let outline = try sRGBColor(try XCTUnwrap(track.borderColor))
                        let accent = try sRGBColor(resolved(appColor, in: appearance))
                        assertSameHue(outline, accent)
                        XCTAssertGreaterThanOrEqual(brightness(outline), brightness(accent))
                        XCTAssertGreaterThanOrEqual(outline.alphaComponent, 0.75)
                    }
                    XCTAssertTrue(row.layer?.animationKeys()?.isEmpty ?? true)
                    XCTAssertTrue(track.animationKeys()?.isEmpty ?? true)
                    XCTAssertTrue(gradient.animationKeys()?.isEmpty ?? true)
                }
            }
        }
    }

    func testDefaultFixedScaleKeepsFullGradientWidthAndOnlyRevealsTheMeasuredPrefix() throws {
        let view = makeView(count: 10)
        let scores = [0.0, 0.04, 8.1, 46, 84, 100, 125]
        view.update(state: .ready(scores.enumerated().map { process($0.offset + 1, score: $0.element) }), count: 10)
        view.layoutSubtreeIfNeeded()
        let expectedRatios = [0.0, 0.0004, 0.081, 0.46, 0.84, 1, 1]
        for (geometry, ratio) in zip(view.gradientPreviewGeometryForTest, expectedRatios) {
            XCTAssertEqual(geometry.gradientWidth, 114)
            XCTAssertEqual(geometry.visibleMaskWidth, 114 * ratio, accuracy: 0.000_001)
            XCTAssertTrue(geometry.usesFixedScale)
        }
        for row in visibleRows(view) {
            let gradient = try gradientLayer(row)
            let mask = try XCTUnwrap(gradient.mask)
            XCTAssertEqual(mask.frame.origin, .zero)
            XCTAssertEqual(mask.frame.height, 10)
            XCTAssertEqual(mask.backgroundColor?.alpha, 1)
            XCTAssertEqual(mask.cornerRadius, 2)
            XCTAssertEqual(gradient.startPoint, CGPoint(x: 0, y: 0.5))
            XCTAssertEqual(gradient.endPoint, CGPoint(x: 1, y: 0.5))
            XCTAssertTrue(mask.animationKeys()?.isEmpty ?? true)
        }
    }

    func testPreviewStyleSwitchesReuseRowsAndRemoveTheFixedScaleMask() throws {
        let view = makeView()
        view.update(state: .ready([8.1, 46, 84].enumerated().map {
            process($0.offset + 1, score: $0.element)
        }), count: 3)
        view.layoutSubtreeIfNeeded()
        let rowIDs = visibleRows(view).map(ObjectIdentifier.init)
        let frames = view.subviews.map(\.frame)
        for style in TopProcessesView.GradientPreviewStyle.allCases + [.fixedScaleHorizontal, .filledWidthHorizontal] {
            view.setGradientPreviewStyle(style)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.subviews.map(\.frame), frames)
            XCTAssertEqual(visibleRows(view).map(ObjectIdentifier.init), rowIDs)
            for (index, row) in visibleRows(view).enumerated() {
                let gradient = try gradientLayer(row)
                let ratio = view.barGeometryForTest[index].ratio
                XCTAssertEqual(gradient.frame.width, style == .fixedScaleHorizontal ? 114 : 114 * ratio,
                               accuracy: 0.000_001)
                XCTAssertEqual(gradient.mask != nil, style == .fixedScaleHorizontal)
                let vertical = style == .vertical || style == .activityTint
                XCTAssertEqual(gradient.startPoint, vertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5))
                XCTAssertEqual(gradient.endPoint, vertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5))
                XCTAssertTrue(gradient.animationKeys()?.isEmpty ?? true)
            }
            if style == .activityTint {
                let low = [0xD4ECFF, 0x90C9F5, 0x5BA5E3]
                let high = [0x78BCFF, 0x187DE0, 0x0754B0]
                for (index, row) in visibleRows(view).enumerated() {
                    for (actual, stops) in zip(try gradientColors(row), zip(low, high)) {
                        let expected = NSColor(rgb: UInt32(stops.0)).blended(
                            withFraction: view.barGeometryForTest[index].ratio, of: NSColor(rgb: UInt32(stops.1)))!
                        try assertColor(actual, matches: expected, in: view.effectiveAppearance)
                    }
                }
            }
        }
    }

    func testDefaultFixedScaleRetainsMaskGeometryAcrossThemesAndHighContrast() throws {
        let view = makeView()
        view.update(state: .ready([8.1, 46, 84].enumerated().map {
            process($0.offset + 1, score: $0.element)
        }), count: 3)
        let originalContrast = ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"]
        defer {
            if let originalContrast { setenv("WATTSON_FORCE_INCREASE_CONTRAST", originalContrast, 1) }
            else { unsetenv("WATTSON_FORCE_INCREASE_CONTRAST") }
        }
        for (name, contrast): (NSAppearance.Name, Bool) in [(.aqua, false), (.darkAqua, false),
                (.accessibilityHighContrastAqua, true), (.accessibilityHighContrastDarkAqua, true)] {
            setenv("WATTSON_FORCE_INCREASE_CONTRAST", contrast ? "1" : "0", 1)
            view.appearance = try XCTUnwrap(NSAppearance(named: name))
            view.viewDidChangeEffectiveAppearance()
            for (geometry, ratio) in zip(view.gradientPreviewGeometryForTest, [0.081, 0.46, 0.84]) {
                XCTAssertEqual(geometry.gradientWidth, 114)
                XCTAssertEqual(geometry.visibleMaskWidth, 114 * ratio, accuracy: 0.000_001)
                XCTAssertTrue(geometry.usesFixedScale)
            }
            if contrast {
                for row in visibleRows(view) {
                    try assertPalette(row, follows: PopoverStyle.blue, in: view.effectiveAppearance, contrast: true)
                }
            }
        }
    }

    func testNativeHelpExplainsActivityMeaningScaleAndCPUConventionWithoutOpeningAWindow() throws {
        let view = makeView()
        let button = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first)
        view.layoutSubtreeIfNeeded()
        XCTAssertFalse(button.isBordered)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.frame.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(button.accessibilityLabel(), "About Process Activity")
        try assertColor(resolved(try XCTUnwrap(button.contentTintColor), in: view.effectiveAppearance),
                        matches: PopoverStyle.secondaryText, in: view.effectiveAppearance)
        XCTAssertNotNil(button.target)
        XCTAssertNotNil(button.action)
        XCTAssertEqual(button.toolTip, "About Activity Score")
        XCTAssertEqual(button.accessibilityHelp(), view.activityHelpForTest)
        for required in ["Activity Score combines CPU usage and idle wakeups",
                         "Higher scores indicate greater process activity",
                         "not measured power consumption", "fixed 0–100 scale",
                         "› marks scores above 100", "CPU 100% means one logical core"] {
            XCTAssertTrue(view.activityHelpForTest.contains(required))
        }
        XCTAssertFalse(view.activityHelpForTest.contains("POWER"))
        XCTAssertFalse(view.activityHelpForTest.contains("macOS top"))
        view.setPresentationActive(false)
        XCTAssertNil(view.helpWindow)
    }

    func testMouseSelectionRevealsOnlySmallInlineForceQuitWithoutMovingMeasurements() throws {
        let view = makeView()
        let values = (41...43).map { identifiedProcess($0) }
        view.update(state: .ready(values), count: 3)
        view.layoutSubtreeIfNeeded()
        let rows = view.processRowsForTest
        let bars = view.barGeometryForTest.map(\.track)
        let labels = rows.map { $0.subviews.compactMap { $0 as? NSTextField } }
        let valueFrames = labels.map { $0[1].frame }
        let detailFrames = labels.map { $0[2].frame }
        var callbacks: [EnergyProcess] = []
        view.forceQuitHandler = { callbacks.append($0) }

        try clickRow(rows[1], point: NSPoint(x: 290, y: 11))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.selectedProcessForTest, values[1])
        XCTAssertEqual(view.selectedRowIndexForTest, 1)
        XCTAssertEqual(view.forceQuitButtonsForTest.map(\.isHidden), [true, false, true])
        let button = view.forceQuitButtonsForTest[1]
        XCTAssertEqual(button.frame.maxX, 326)
        XCTAssertEqual(button.frame.minY, 4)
        XCTAssertEqual(button.frame.height, 16)
        XCTAssertEqual(button.frame.width, 38)
        XCTAssertTrue(button.isBordered)
        XCTAssertNotNil(button.image)
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(labels[1][0].frame, NSRect(x: 0, y: 2, width: 132, height: 20))
        XCTAssertEqual(labels[0][0].frame, NSRect(x: 0, y: 2, width: 132, height: 20))
        XCTAssertEqual(view.barGeometryForTest.map(\.track), bars)
        XCTAssertEqual(labels.map { $0[1].frame }, valueFrames)
        XCTAssertEqual(labels.map { $0[2].frame }, detailFrames)
        XCTAssertEqual(labels.map { $0[1].isHidden }, [false, true, false])
        XCTAssertTrue(callbacks.isEmpty)

        // A second click, including AppKit's double-click event, only cancels selection.
        try clickRow(rows[1], point: NSPoint(x: 80, y: 11), clickCount: 2)
        view.layoutSubtreeIfNeeded()
        XCTAssertNil(view.selectedProcessForTest)
        XCTAssertTrue(view.forceQuitButtonsForTest.allSatisfy(\.isHidden))
        XCTAssertTrue(labels.allSatisfy { !$0[1].isHidden })
        XCTAssertEqual(labels[1][0].frame, NSRect(x: 0, y: 2, width: 132, height: 20))
        XCTAssertTrue(callbacks.isEmpty)
    }

    func testSelectedCapsuleKeepsUniformWidthWithoutMovingOtherContent() throws {
        for compact in [false, true] {
            let view = makeView(count: 1, compact: compact)
            view.update(state: .ready([identifiedProcess(41, score: 8.1)]), count: 1, compact: compact)
            view.layoutSubtreeIfNeeded()
            let row = try XCTUnwrap(view.processRowsForTest.first)
            try clickRow(row, point: NSPoint(x: 40, y: 11))
            let labels = row.subviews.compactMap { $0 as? NSTextField }
            let originalFrames = labels.map(\.frame)
            for score in [8.1, 84, 125.5, 0.04, 0, 999.96, Double.greatestFiniteMagnitude, 8.1] {
                view.update(state: .ready([identifiedProcess(41, score: score)]), count: 1, compact: compact)
                view.layoutSubtreeIfNeeded()
                let button = view.forceQuitButtonsForTest[0]
                XCTAssertEqual(button.frame.width, 38)
                XCTAssertEqual(button.frame.maxX, 326)
                XCTAssertEqual(button.frame.midX, 307)
                XCTAssertEqual(button.frame.minY, 4)
                XCTAssertEqual(button.frame.height, 16)
                XCTAssertGreaterThan(button.frame.width, button.frame.height)
                XCTAssertFalse(button.isHidden)
                XCTAssertTrue(labels[1].isHidden)
                XCTAssertEqual(labels.map(\.frame), originalFrames)
                XCTAssertEqual(view.barGeometryForTest[0].track, NSRect(x: 144, y: 6, width: 116, height: 12))
            }
        }
    }

    func testSelectedCrossKeepsItsButtonHitAndCallsBackWithCurrentImmutableProcess() throws {
        let view = makeView()
        let original = identifiedProcess(41)
        view.update(state: .ready([original]), count: 3)
        view.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(view.processRowsForTest.first)
        try clickRow(row, point: NSPoint(x: 60, y: 32))
        view.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(view.forceQuitButtonsForTest.first)
        let buttonPoint = row.convert(NSPoint(x: button.frame.midX, y: button.frame.midY), to: view)
        XCTAssertTrue(row.hitTest(buttonPoint) === button)

        let refreshed = identifiedProcess(41, score: 91)
        view.update(state: .ready([refreshed]), count: 3)
        var callbacks: [EnergyProcess] = []
        view.forceQuitHandler = { callbacks.append($0) }
        button.performClick(nil)
        XCTAssertEqual(callbacks, [refreshed])
        XCTAssertEqual(view.selectedProcessForTest, refreshed)
        XCTAssertFalse(button.isHidden)
        XCTAssertEqual(row.accessibilityRole(), .group)
        XCTAssertEqual(row.accessibilityChildren()?.count, 1)
        XCTAssertTrue(row.accessibilityChildren()?.first as? NSButton === button)
        XCTAssertTrue(button.isAccessibilityElement())
        XCTAssertEqual(button.accessibilityLabel(), "Force Quit Process 41")
    }

    func testMissingTrustedIdentityShowsDisabledCrossAndNeverCallsBack() throws {
        let view = makeView()
        let reading = process(42, score: 10)
        view.update(state: .ready([reading]), count: 3)
        view.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(view.processRowsForTest.first)
        try clickRow(row, point: NSPoint(x: 210, y: 12))
        let button = try XCTUnwrap(view.forceQuitButtonsForTest.first)
        XCTAssertFalse(button.isHidden)
        XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.toolTip, "Force Quit Unavailable")
        XCTAssertTrue(button.isAccessibilityElement())
        var callbacks = 0
        view.forceQuitHandler = { _ in callbacks += 1 }
        button.performClick(nil)
        XCTAssertEqual(callbacks, 0)
        view.update(state: .ready([process(42, score: 20)]), count: 3)
        XCTAssertEqual(view.selectedProcessForTest?.pid, 42)
        view.update(state: .ready([EnergyProcess(pid: 42, name: "Renamed", energyImpact: 20,
                                               cpuPercent: 20, idleWakeupsPerSecond: 0)]), count: 3)
        XCTAssertNil(view.selectedProcessForTest)
    }

    func testSelectionFollowsExactIdentityAcrossRankingAndClearsForPIDReuse() throws {
        let view = makeView()
        let first = identifiedProcess(41)
        let second = identifiedProcess(42)
        view.update(state: .ready([first, second]), count: 3)
        view.layoutSubtreeIfNeeded()
        try clickRow(view.processRowsForTest[0], point: NSPoint(x: 40, y: 11))
        let updated = identifiedProcess(41, score: 99)
        view.update(state: .ready([second, updated]), count: 3)
        XCTAssertEqual(view.selectedProcessForTest, updated)
        XCTAssertEqual(view.selectedRowIndexForTest, 1)
        XCTAssertEqual(view.forceQuitButtonsForTest.map(\.isHidden), [true, false])
        let samePIDNewStart = identifiedProcess(41, startedAt: 99)
        view.update(state: .ready([second, samePIDNewStart]), count: 3)
        XCTAssertNil(view.selectedProcessForTest)
        view.layoutSubtreeIfNeeded()
        try clickRow(view.processRowsForTest[1], point: NSPoint(x: 40, y: 11))
        let samePIDNewAudit = identifiedProcess(41, startedAt: 99, tokenByte: 9)
        view.update(state: .ready([second, samePIDNewAudit]), count: 3)
        XCTAssertNil(view.selectedProcessForTest)
        XCTAssertTrue(view.forceQuitButtonsForTest.allSatisfy(\.isHidden))
    }

    func testStatusCountCompactAndPresentationLifecycleManageSelectionIndependentlyOfContentGuard() throws {
        let view = makeView()
        let state = TopProcessesState.ready([identifiedProcess(41), identifiedProcess(42)])
        func selectFirst(count: Int = 3, compact: Bool = false) throws {
            view.update(state: state, count: count, compact: compact)
            view.layoutSubtreeIfNeeded()
            try clickRow(view.processRowsForTest[0], point: NSPoint(x: 40, y: 11))
            XCTAssertNotNil(view.selectedProcessForTest)
        }
        try selectFirst()
        for compact in [true, false, true] {
            view.update(state: state, count: 3, compact: compact)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.selectedProcessForTest?.pid, 41)
            XCTAssertEqual(view.forceQuitButtonsForTest[0].frame.height, 16)
            XCTAssertEqual(view.forceQuitButtonsForTest[0].frame.maxX, 326)
        }
        view.update(state: state, count: 2, compact: true)
        XCTAssertNil(view.selectedProcessForTest)
        for status: TopProcessesState in [.loading, .unavailable, .ready([])] {
            try selectFirst()
            view.update(state: status, count: 3)
            XCTAssertNil(view.selectedProcessForTest)
            XCTAssertTrue(view.processRowsForTest.isEmpty)
        }
        try selectFirst()
        let updates = view.contentUpdatesForTest
        view.setPresentationActive(false)
        view.setPresentationActive(true)
        view.update(state: state, count: 3)
        XCTAssertEqual(view.contentUpdatesForTest, updates)
        XCTAssertNil(view.selectedProcessForTest)
        XCTAssertTrue(view.forceQuitButtonsForTest.allSatisfy(\.isHidden))
        try selectFirst()
        view.isHidden = true
        XCTAssertNil(view.selectedProcessForTest)
        view.isHidden = false
        try selectFirst()
        view.viewDidMoveToWindow()
        XCTAssertNil(view.selectedProcessForTest)
    }

    func testKeyboardAndAccessibilitySelectionExposeCrossWithoutTerminating() throws {
        let view = makeView()
        view.update(state: .ready([identifiedProcess(41), identifiedProcess(42)]), count: 3)
        view.layoutSubtreeIfNeeded()
        let rows = view.processRowsForTest
        var callbacks = 0
        view.forceQuitHandler = { _ in callbacks += 1 }
        XCTAssertTrue(rows[0].acceptsFirstResponder)
        XCTAssertTrue(rows[0].accessibilityPerformPress())
        XCTAssertEqual(view.selectedRowIndexForTest, 0)
        rows[0].keyDown(with: try keyEvent(125))
        XCTAssertEqual(view.selectedRowIndexForTest, 1)
        rows[1].keyDown(with: try keyEvent(49))
        XCTAssertNil(view.selectedRowIndexForTest)
        rows[1].keyDown(with: try keyEvent(36))
        XCTAssertEqual(view.selectedRowIndexForTest, 1)
        rows[1].keyDown(with: try keyEvent(53))
        XCTAssertNil(view.selectedRowIndexForTest)
        XCTAssertEqual(callbacks, 0)
        XCTAssertTrue(rows.allSatisfy { $0.accessibilityChildren()?.isEmpty == true })
        XCTAssertTrue(view.forceQuitButtonsForTest.allSatisfy { !$0.isAccessibilityElement() })
    }

    func testNeutralSelectionAdaptsToLightDarkAndHighContrastWithoutChangingGradient() throws {
        let view = makeView()
        view.update(state: .ready([identifiedProcess(41)]), count: 3)
        view.layoutSubtreeIfNeeded()
        try clickRow(view.processRowsForTest[0], point: NSPoint(x: 40, y: 11))
        let row = view.processRowsForTest[0]
        let originalContrast = ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"]
        defer {
            if let originalContrast { setenv("WATTSON_FORCE_INCREASE_CONTRAST", originalContrast, 1) }
            else { unsetenv("WATTSON_FORCE_INCREASE_CONTRAST") }
        }
        for (name, contrast): (NSAppearance.Name, Bool) in [(.aqua, false), (.darkAqua, false),
                (.accessibilityHighContrastAqua, true), (.accessibilityHighContrastDarkAqua, true)] {
            setenv("WATTSON_FORCE_INCREASE_CONTRAST", contrast ? "1" : "0", 1)
            view.appearance = try XCTUnwrap(NSAppearance(named: name))
            view.refreshAppearance()
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(row.layer?.backgroundColor?.alpha ?? 0, contrast ? 0.08 : 0.045, accuracy: 0.000_001)
            XCTAssertEqual(row.layer?.borderWidth, contrast ? 1 : 0)
            XCTAssertEqual(view.barGeometryForTest[0].track, NSRect(x: 144, y: 6, width: 116, height: 12))
            try assertPalette(row, follows: PopoverStyle.blue, in: view.effectiveAppearance, contrast: contrast)
            XCTAssertTrue(row.layer?.animationKeys()?.isEmpty ?? true)
        }
    }

    private func identifiedProcess(_ pid: Int, startedAt: UInt64 = 7, tokenByte: UInt8 = 1,
                                   score: Double = 40) -> EnergyProcess {
        var token = audit_token_t()
        token.val.5 = UInt32(pid)
        token.val.7 = UInt32(tokenByte)
        let identity = ProcessIdentity(pid: Int32(pid), startedAt: startedAt,
                                       auditToken: withUnsafeBytes(of: &token) { Data($0) })
        XCTAssertTrue(identity.isValid)
        return EnergyProcess(pid: Int32(pid), name: "Process \(pid)", energyImpact: score,
                             cpuPercent: score, idleWakeupsPerSecond: 0, terminationIdentity: identity)
    }

    func testRoundedHoverSummaryFitsTwoLinesWithoutRepeatingTheExplanation() throws {
        let view = makeView(count: 1, compact: true)
        let reading = EnergyProcess(pid: 86572, name: "backupd", energyImpact: 92.41859130318788,
                                     cpuPercent: 92.41859130318788, idleWakeupsPerSecond: 0)
        view.update(state: .ready([reading]), count: 1, compact: true)
        let row = try XCTUnwrap(view.processRowsForTest.first)
        let summary = "Score 92.4 · CPU 92.4% · Wakeups 0/s"
        XCTAssertEqual(row.toolTip, "backupd · PID 86572\n\(summary)")
        XCTAssertEqual(row.toolTip?.split(separator: "\n").count, 2)
        XCTAssertFalse(row.toolTip?.contains("combines") ?? true)
        XCTAssertFalse(row.toolTip?.contains("18788") ?? true)
        for field in row.subviews.compactMap({ $0 as? NSTextField }).dropFirst() {
            XCTAssertEqual(field.toolTip, summary)
        }
    }

    func testSingleSharedReflectionTracksOnlyTheRightActionAndClearsOnDismissal() throws {
        let view = makeView()
        view.update(state: .ready([identifiedProcess(41), identifiedProcess(42)]), count: 3)
        view.layoutSubtreeIfNeeded()
        let feedback = view.forceQuitFeedbackForTest
        XCTAssertEqual(view.subviews.compactMap { $0 as? FooterHoverFeedbackView }.count, 1)
        XCTAssertTrue(feedback.regionsForTest.isEmpty)
        try clickRow(view.processRowsForTest[1], point: NSPoint(x: 70, y: 11))
        view.layoutSubtreeIfNeeded()
        let button = view.forceQuitButtonsForTest[1]
        XCTAssertEqual(feedback.regionsForTest, [.init(rect: button.convert(button.bounds, to: feedback), enabled: true)])
        XCTAssertNil(feedback.hitTest(.zero))
        view.setPresentationActive(false)
        XCTAssertTrue(feedback.regionsForTest.isEmpty)
        XCTAssertEqual(feedback.glowForTest.opacity, 0)
        XCTAssertTrue(feedback.glowForTest.animationKeys()?.isEmpty ?? true)
    }

    private func clickRow(_ row: NSView, point: NSPoint, clickCount: Int = 1) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
                                                    modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                    context: nil, eventNumber: 1, clickCount: clickCount, pressure: 1))
        let pointInParent = row.convert(point, to: row.superview)
        let target = try XCTUnwrap(row.hitTest(pointInParent))
        XCTAssertTrue(target === row)
        target.mouseDown(with: event)
    }

    private func keyEvent(_ keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                      isARepeat: false, keyCode: keyCode))
    }

    private func makeView(count: Int = 3, compact: Bool = false) -> TopProcessesView {
        let view = TopProcessesView()
        view.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                            height: TopProcessesView.preferredHeight(count: count, compact: compact))
        return view
    }

    private func process(_ pid: Int, score: Double) -> EnergyProcess {
        EnergyProcess(pid: Int32(pid), name: "Process \(pid)", energyImpact: score,
                      cpuPercent: score, idleWakeupsPerSecond: 0)
    }

    private func processes(_ count: Int) -> [EnergyProcess] {
        (1...count).map { process($0, score: Double($0) + 0.26) }
    }

    private func visibleRows(_ view: TopProcessesView) -> [NSView] {
        view.subviews.filter { !$0.isHidden && $0.identifier?.rawValue == "top-processes.row" }
    }

    private func gradientColors(_ row: NSView) throws -> [CGColor] {
        try XCTUnwrap(gradientLayer(row).colors as? [CGColor])
    }

    private func gradientLayer(_ row: NSView) throws -> CAGradientLayer {
        let track = try XCTUnwrap(row.layer?.sublayers?.first { $0.name == "top-processes.track" })
        return try XCTUnwrap(track.sublayers?.first as? CAGradientLayer)
    }

    private func assertPalette(_ row: NSView, follows appColor: NSColor, in appearance: NSAppearance,
                               contrast: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let colors = try gradientColors(row)
        XCTAssertEqual(colors.count, 3, file: file, line: line)
        guard colors.count == 3 else { return }
        let accent = try sRGBColor(resolved(appColor, in: appearance))
        let stops = try colors.map(sRGBColor)
        let button = try XCTUnwrap(row.subviews.compactMap { $0 as? ProcessActionButton }.first)
        try assertColor(button.tintColor.cgColor, matches: stops[2], in: appearance, file: file, line: line)
        for color in stops {
            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001, file: file, line: line)
            assertSameHue(color, accent, file: file, line: line)
        }
        try assertColor(colors[1], matches: accent, in: appearance, file: file, line: line)
        if contrast {
            for color in colors {
                try assertColor(color, matches: accent, in: appearance, file: file, line: line)
            }
        } else {
            XCTAssertGreaterThanOrEqual(brightness(stops[0]), brightness(stops[1]), file: file, line: line)
            XCTAssertGreaterThanOrEqual(brightness(stops[1]), brightness(stops[2]), file: file, line: line)
            XCTAssertGreaterThan(brightness(stops[0]), brightness(stops[2]), file: file, line: line)
        }
    }

    private func assertSameHue(_ color: NSColor, _ accent: NSColor,
                               file: StaticString = #filePath, line: UInt = #line) {
        if accent.saturationComponent < 0.01 {
            XCTAssertEqual(color.redComponent, color.greenComponent, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(color.greenComponent, color.blueComponent, accuracy: 0.001, file: file, line: line)
        } else {
            let distance = abs(color.hueComponent - accent.hueComponent)
            // Native NSColor blending can shift hue slightly during color-space conversion.
            XCTAssertLessThan(min(distance, 1 - distance), 0.02, file: file, line: line)
        }
    }

    private func brightness(_ color: NSColor) -> CGFloat {
        0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }

    private func sRGBColor(_ color: CGColor) throws -> NSColor {
        try XCTUnwrap(NSColor(cgColor: color)?.usingColorSpace(.sRGB))
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
}
