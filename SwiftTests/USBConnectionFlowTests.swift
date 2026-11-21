import AppKit
import XCTest
@testable import Wattson

final class USBConnectionFlowTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suite = testDefaultsSuite("USBConnectionFlow")
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func flow() -> PowerFlowView {
        let view = PowerFlowView()
        view.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                            height: PowerFlowView.preferredHeight)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private var states: [(PowerSnapshot, String, Int)] {
        [
            (PowerSnapshot(percent: 70, batteryW: -39.7, systemW: 39.7), "batteryOutputSplit", 1),
            (PowerSnapshot(percent: 70, plugged: true, adapterW: 68,
                           batteryW: 22.2, systemW: 45.8), "adapterOutputSplit", 2),
            (PowerSnapshot(percent: 100, plugged: true, adapterW: 40,
                           systemW: 40, systemChargingState: .full), "adapterOutputSplit", 2),
            (PowerSnapshot(percent: 70, plugged: true, adapterW: 40,
                           systemW: 40), "adapterOutputSplit", 2),
            (PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                           batteryW: -9.7, systemW: 39.7), "mixedOutputSplit", 3),
        ]
    }

    func testConnectionAppearsWithoutWattsAcrossThemesAndPowerStates() throws {
        let view = flow()
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { view.setAnimationsEnabled(false); window.contentView = nil; window.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            view.appearance = NSAppearance(named: appearance)
            for (baseline, topology, outputBranch) in states {
                for value: Double? in [nil, 0, -1, .nan, .infinity, baseline.systemW + 1] {
                    var pending = baseline
                    pending.hasConnectedUSBDevice = true
                    pending.deviceOutputW = value
                    view.update(snapshot: pending, animated: false)
                    view.setAnimationsEnabled(true)
                    view.layoutSubtreeIfNeeded()

                    let presentations = view.nodePresentationsForTest
                    XCTAssertEqual(view.topologyForTest, topology)
                    XCTAssertEqual(presentations.filter { $0.caption == "USB Device" }.map(\.value), ["Connected"])
                    XCTAssertEqual(presentations.filter { $0.caption == "System Total" }.map(\.value),
                                   [PopoverStyle.watts(baseline.systemW)])
                    XCTAssertFalse(presentations.contains { $0.caption == "Device Output" || $0.caption == "Mac Load" })
                    XCTAssertEqual(view.branchThicknessesForTest[outputBranch], 0)
                    XCTAssertEqual(view.branchParticleCountsForTest[outputBranch], 0)
                    XCTAssertFalse(view.fusionParticlesVisibleForTest)
                    XCTAssertFalse(view.connectionGlowForTest.container.isHidden)
                    XCTAssertEqual(view.connectionGlowForTest.container.opacity, 1)
                    let glowColors = try XCTUnwrap(view.connectionGlowForTest.lightLayersForTest.last?.colors as? [CGColor])
                    let glowPeak = try XCTUnwrap(glowColors.dropFirst(4).first)
                    view.effectiveAppearance.performAsCurrentDrawingAppearance {
                        XCTAssertEqual(glowPeak, view.conditionColorForTest.withAlphaComponent(0.42).cgColor)
                    }
                    XCTAssertEqual(view.bounds.height, 224)
                    XCTAssertTrue(view.nodeContentsFitForTest)
                    XCTAssertEqual(try XCTUnwrap(view.idleEndpointXsForTest.last), 269.5, accuracy: 0.001)
                    let frames = view.nodeFramesForTest
                    for (index, frame) in frames.enumerated() {
                        XCTAssertTrue(frames.dropFirst(index + 1).allSatisfy {
                            NSIntersectionRect(frame, $0).isEmpty
                        })
                    }
                    let fields = (view.accessibilityChildren() ?? []).compactMap { $0 as? NSTextField }
                    let usb = try XCTUnwrap(fields.first { $0.accessibilityLabel() == "USB Device" })
                    XCTAssertEqual(usb.accessibilityValue(), "Connected")
                    XCTAssertTrue(usb.accessibilityHelp()?.contains("System Total") == true)
                    XCTAssertEqual(pending.systemW, baseline.systemW)
                    XCTAssertEqual(pending.conservationError, baseline.conservationError)
                }
            }
        }
    }

    func testMeasuredAndDisconnectedTransitionsDoNotKeepConnectionHelpOrInventPower() throws {
        let view = flow()
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.setAnimationsEnabled(true)
        defer { view.setAnimationsEnabled(false); window.contentView = nil; window.close() }
        for (baseline, _, outputBranch) in states {
            var pending = baseline
            pending.hasConnectedUSBDevice = true
            pending.deviceOutputW = 7.5
            pending.deviceOutputIsComplete = false
            view.update(snapshot: pending, animated: false)
            view.layoutSubtreeIfNeeded()
            let pendingFrames = view.nodeFramesForTest
            XCTAssertEqual(view.branchParticleCountsForTest[outputBranch], 0)
            XCTAssertTrue(view.nodePresentationsForTest.contains { $0.caption == "USB Device" && $0.value == "Connected" })
            XCTAssertFalse(view.connectionGlowForTest.container.isHidden)

            var measured = pending
            measured.deviceOutputIsComplete = true
            view.update(snapshot: measured, animated: false)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.nodeFramesForTest, pendingFrames)
            XCTAssertTrue(view.connectionGlowForTest.container.isHidden)
            XCTAssertTrue(view.nodePresentationsForTest.contains { $0.caption == "Device Output" && $0.value == "7.5 W" })
            XCTAssertTrue(view.nodePresentationsForTest.contains {
                $0.caption == "Mac Load" && $0.value == PopoverStyle.watts(baseline.systemW - 7.5)
            })
            let measuredPresentation = view.nodePresentationsForTest.map { $0.caption + ":" + $0.value }
            measured.hasConnectedUSBDevice = false
            view.update(snapshot: measured, animated: false)
            XCTAssertEqual(view.nodePresentationsForTest.map { $0.caption + ":" + $0.value }, measuredPresentation,
                           "A power-only device need not enumerate over USB")

            view.update(snapshot: baseline, animated: false)
            view.layoutSubtreeIfNeeded()
            XCTAssertFalse(view.nodePresentationsForTest.contains { $0.caption == "USB Device" || $0.caption == "Device Output" })
            for field in (view.accessibilityChildren() ?? []).compactMap({ $0 as? NSTextField }) {
                XCTAssertNil(field.accessibilityHelp(), "A reused battery node must not retain USB help")
            }
        }
    }

    func testPendingConnectionInBatteryDeadbandShowsCapacityWithoutEnergyParticles() {
        let view = flow()
        defer { view.setAnimationsEnabled(false) }
        for batteryW in [-0.3, 0, 0.2] {
            var snapshot = PowerSnapshot(percent: 70, batteryW: batteryW, systemW: 0)
            snapshot.hasConnectedUSBDevice = true
            view.update(snapshot: snapshot, animated: false)
            view.setAnimationsEnabled(true)
            view.layoutSubtreeIfNeeded()
            XCTAssertTrue(view.nodePresentationsForTest.contains { $0.caption == "Battery 70%" && $0.value == "70 %" })
            XCTAssertTrue(view.nodePresentationsForTest.contains { $0.caption == "USB Device" && $0.value == "Connected" })
            XCTAssertTrue(view.branchThicknessesForTest.allSatisfy { $0 == 0 })
            XCTAssertTrue(view.branchParticleCountsForTest.allSatisfy { $0 == 0 })
        }
    }

    func testPendingUSBUsesTheFutureDeviceBranchAtTheSharedOutlet() throws {
        let fixtures: [PowerSnapshot] = [
            .init(percent: 70, plugged: true, adapterW: 68, batteryW: 22.2,
                  systemW: 45.8, hasConnectedUSBDevice: true),
            .init(percent: 100, plugged: true, adapterW: 40, systemW: 40,
                  hasConnectedUSBDevice: true, systemChargingState: .full),
            .init(percent: 70, batteryW: -39.7, systemW: 39.7, hasConnectedUSBDevice: true),
            .init(percent: 70, plugged: true, adapterW: 30, batteryW: -9.7,
                  systemW: 39.7, hasConnectedUSBDevice: true),
            .init(percent: 70, hasConnectedUSBDevice: true),
        ]
        for snapshot in fixtures {
            let scene = PowerFlowScene.make(snapshot: snapshot)
            let dormant = scene.edges[FlowEdgeRole.deviceOutput.rawValue]
            let common = scene.edges[FlowEdgeRole.common.rawValue]
            let waiting = try XCTUnwrap(scene.idleDevice)
            XCTAssertEqual(dormant.startWidth, 0)
            XCTAssertEqual(dormant.endWidth, 0)
            XCTAssertEqual(waiting.start.x, max(58.5, dormant.geometry.start.x))
            XCTAssertEqual(waiting.start.y, dormant.geometry.start.y)
            XCTAssertEqual(waiting.start.y, scene.jointEnd.y + common.endWidth / 2, accuracy: 0.001,
                           "The USB connection uses the bottom output slot at the shared outlet")
            XCTAssertEqual(waiting.control1, dormant.geometry.control1)
            XCTAssertEqual(waiting.control2, dormant.geometry.control2)
            XCTAssertEqual(waiting.end, CGPoint(x: scene.nodes[3].x - 18.5, y: dormant.geometry.end.y))
            XCTAssertGreaterThanOrEqual(waiting.start.x, 58.5)
            XCTAssertLessThan(waiting.start.x, waiting.end.x)
            if scene.layout == .mixedOutputSplit {
                XCTAssertEqual(waiting.start.x, scene.jointEnd.x, "Mixed supply branches from the fusion outlet")
            } else {
                XCTAssertEqual(waiting.start.x, 58.5, "Normal supply branches at the source outlet, not midway along a bar")
            }
        }
    }

    func testFullPendingBranchStaysBelowTheIdleBatteryConnectionAtLowLoads() throws {
        for watts in [0.01, 0.1, 1, 5, 40] {
            let scene = PowerFlowScene.make(snapshot: .init(percent: 100, plugged: true,
                adapterW: watts, systemW: watts, hasConnectedUSBDevice: true, systemChargingState: .full))
            let battery = try XCTUnwrap(scene.idleBattery)
            let device = try XCTUnwrap(scene.idleDevice)
            XCTAssertEqual(battery.start.y, battery.end.y)
            XCTAssertEqual(battery.control1.y, battery.start.y)
            XCTAssertEqual(battery.control2.y, battery.start.y)
            XCTAssertGreaterThanOrEqual(device.start.x, 58.5, "The fork at \(watts) W must clear the Adapter well")
            for point in [device.start, device.control1, device.control2, device.end] {
                XCTAssertGreaterThan(point.y, battery.start.y,
                                     "All control points must stay below the idle-battery line at \(watts) W")
            }
        }
    }

    func testPendingConnectionKeepsInstrumentTotalsAndUnknownOutputValue() {
        Settings.ringMetrics = [.systemLoad, .deviceOutput]
        let gauge = RingGaugeView()
        let lanes = LaneView()
        var snapshot = PowerSnapshot(percent: 70, batteryW: -39.7, systemW: 39.7)
        snapshot.hasConnectedUSBDevice = true
        gauge.update(snapshot: snapshot)
        lanes.update(snapshot: snapshot)
        XCTAssertEqual(gauge.readingForTest(.systemLoad)?.caption, "System Total")
        XCTAssertEqual(gauge.readingForTest(.systemLoad)?.value, "39.7 W")
        XCTAssertEqual(gauge.readingForTest(.deviceOutput)?.value, "—")
        XCTAssertTrue(lanes.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "System Total" })
        snapshot.hasConnectedUSBDevice = false
        gauge.update(snapshot: snapshot)
        lanes.update(snapshot: snapshot)
        XCTAssertEqual(gauge.readingForTest(.systemLoad)?.caption, "System Load")
        XCTAssertTrue(lanes.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "System Load" })
    }
}
