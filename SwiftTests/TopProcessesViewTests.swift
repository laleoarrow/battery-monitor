import AppKit
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
                XCTAssertEqual(bar.fill.width, 114 * bar.ratio, accuracy: 0.001)
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
        XCTAssertEqual(view.barGeometryForTest[0].fill.width, 0)
        XCTAssertEqual(view.barGeometryForTest[1].fill.width, 0.0456, accuracy: 0.000_001)
        for (index, score) in scores.enumerated() {
            let field = values[index]
            XCTAssertEqual(field.alignment, .right)
            XCTAssertEqual(field.font, PopoverStyle.mono(13, .semibold))
            let textWidth = field.stringValue.size(withAttributes: [.font: try XCTUnwrap(field.font)]).width
            XCTAssertLessThanOrEqual(textWidth, field.frame.width - 4)
            XCTAssertTrue(field.toolTip?.contains("Activity Score \(score)") == true)
            let marker = try XCTUnwrap(rows[index].subviews.compactMap { $0 as? NSImageView }
                .first { $0.identifier?.rawValue == "top-processes.overflow" })
            XCTAssertEqual(marker.isHidden, score <= 100)
            XCTAssertEqual(marker.frame, NSRect(x: 262, y: 6, width: 8, height: 12))
            XCTAssertGreaterThan(marker.frame.minX, view.barGeometryForTest[index].track.maxX)
            XCTAssertLessThan(marker.frame.maxX, field.frame.minX)
            XCTAssertFalse(marker.isAccessibilityElement())
            XCTAssertNotNil(marker.image)
        }
        XCTAssertTrue(rows.last?.accessibilityValue() as? String == values.last?.toolTip)
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
        XCTAssertTrue((row.accessibilityValue() as? String)?.contains("CPU 72.0%; idle wakeups 240.0 per second") == true)
        XCTAssertTrue(row.accessibilityHelp()?.contains("not measured power consumption") == true)
        XCTAssertTrue(row.subviews.allSatisfy { !$0.isAccessibilityElement() })
        let images = row.subviews.compactMap { $0 as? NSImageView }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.identifier?.rawValue, "top-processes.overflow")
        XCTAssertTrue(images.first?.isHidden == true)
    }

    func testChangingMeasurementsOrRankReusesRowsAndChangesWidthAndValueWithoutChangingPalette() throws {
        let view = makeView()
        let original = processes(3)
        view.update(state: .ready(original), count: 3)
        let rows = visibleRows(view)
        let fields = rows.flatMap { $0.subviews }.map(ObjectIdentifier.init)
        let originalColors = try gradientColors(try XCTUnwrap(rows.first))
        for iteration in 0..<50 {
            let updated = original.reversed().map {
                EnergyProcess(pid: $0.pid, name: $0.name, energyImpact: Double(iteration),
                              cpuPercent: Double(iteration), idleWakeupsPerSecond: 0)
            }
            view.update(state: .ready(updated), count: 3)
        }
        XCTAssertEqual(visibleRows(view).map(ObjectIdentifier.init), rows.map(ObjectIdentifier.init))
        XCTAssertEqual(visibleRows(view).flatMap { $0.subviews }.map(ObjectIdentifier.init), fields)
        let updatedColors = try gradientColors(try XCTUnwrap(rows.first))
        XCTAssertEqual(updatedColors, originalColors)
        XCTAssertEqual(view.barGeometryForTest.map(\.ratio), [0.49, 0.49, 0.49])
        for row in visibleRows(view) {
            let value = try XCTUnwrap(row.subviews.compactMap { $0 as? NSTextField }.dropFirst().first)
            XCTAssertEqual(value.stringValue, "49.0")
            XCTAssertEqual(try gradientColors(row), originalColors)
        }
    }

    func testEveryFillUsesTheSameCompleteHorizontalLightToDarkBlueGradientIncludingShortBars() throws {
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
        let expectedPalette = [0x9CDCFF, 0x2C9DFF, 0x0B69D9].map { NSColor(rgb: $0) }
        for row in rows {
            let gradient = try gradientLayer(row)
            XCTAssertEqual(gradient.startPoint, CGPoint(x: 0, y: 0.5))
            XCTAssertEqual(gradient.endPoint, CGPoint(x: 1, y: 0.5))
            XCTAssertEqual(gradient.locations, [0, 0.45, 1])
            for (actual, expected) in zip(try gradientColors(row), expectedPalette) {
                try assertColor(actual, matches: expected, in: view.effectiveAppearance)
            }
            XCTAssertEqual(try gradientColors(row), try gradientColors(rows[0]))
        }
        for (bar, expected) in zip(view.barGeometryForTest, [0.081, 0.46, 0.84]) {
            XCTAssertEqual(bar.ratio, expected, accuracy: 0.000_001)
        }
        // The gradient belongs to each filled segment, so even an 8.1-point
        // reading reaches the dark-blue endpoint within its short fill.
        XCTAssertEqual(try gradientLayer(rows[0]).frame.width, 114 * 0.081, accuracy: 0.000_001)
    }

    func testGradientAndOutlineFollowLightDarkAndHighContrastWithoutAnimations() throws {
        let view = makeView()
        view.update(state: .ready([8.1, 46, 84].enumerated().map {
            process($0.offset + 1, score: $0.element)
        }), count: 3)
        view.layoutSubtreeIfNeeded()
        let frames = view.subviews.map(\.frame)
        let valueColors = try visibleRows(view).map { try gradientColors($0) }
        let originalContrast = ProcessInfo.processInfo.environment["WATTSON_FORCE_INCREASE_CONTRAST"]
        defer {
            if let originalContrast { setenv("WATTSON_FORCE_INCREASE_CONTRAST", originalContrast, 1) }
            else { unsetenv("WATTSON_FORCE_INCREASE_CONTRAST") }
        }
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
            for (index, row) in visibleRows(view).enumerated() {
                let track = try XCTUnwrap(row.layer?.sublayers?.first { $0.name == "top-processes.track" })
                let gradient = try XCTUnwrap(track.sublayers?.first as? CAGradientLayer)
                let colors = try XCTUnwrap(gradient.colors as? [CGColor])
                XCTAssertEqual(colors.count, 3)
                XCTAssertEqual(gradient.locations, [0, 0.45, 1])
                XCTAssertEqual(gradient.startPoint, CGPoint(x: 0, y: 0.5))
                XCTAssertEqual(gradient.endPoint, CGPoint(x: 1, y: 0.5))
                XCTAssertEqual(track.borderWidth, 1)
                XCTAssertEqual(track.backgroundColor?.alpha, 0)
                if contrast {
                    try assertColor(track.borderColor, matches: .labelColor, in: appearance)
                    for color in colors { try assertColor(color, matches: .systemBlue, in: appearance) }
                } else {
                    let dark = PopoverStyle.isDark(appearance)
                    try assertColor(track.borderColor, matches: NSColor(rgb: dark ? 0xDCEEFF : 0xAAC7DE,
                                                                         alpha: dark ? 0.75 : 1), in: appearance)
                    XCTAssertEqual(colors, valueColors[index])
                }
                XCTAssertTrue(row.layer?.animationKeys()?.isEmpty ?? true)
                XCTAssertTrue(track.animationKeys()?.isEmpty ?? true)
                XCTAssertTrue(gradient.animationKeys()?.isEmpty ?? true)
            }
        }
    }

    func testFixedScalePreviewKeepsFullGradientWidthAndOnlyRevealsTheMeasuredPrefix() throws {
        let view = makeView(count: 10)
        view.setGradientPreviewStyle(.fixedScaleHorizontal)
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

    func testFixedScalePreviewRetainsMaskGeometryAcrossThemesAndHighContrast() throws {
        let view = makeView()
        view.setGradientPreviewStyle(.fixedScaleHorizontal)
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
                    for color in try gradientColors(row) {
                        try assertColor(color, matches: .systemBlue, in: view.effectiveAppearance)
                    }
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
        XCTAssertEqual(button.toolTip, view.activityHelpForTest)
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

    private func makeView(count: Int = 3) -> TopProcessesView {
        let view = TopProcessesView()
        view.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                            height: TopProcessesView.preferredHeight(count: count))
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
