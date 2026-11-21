import AppKit
import XCTest
@testable import Wattson

final class USBConnectionGlowTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private let bounds = CGRect(x: 0, y: 0, width: 328, height: 224)

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suite = testDefaultsSuite("USBConnectionGlow")
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func pending() -> PowerSnapshot {
        PowerSnapshot(percent: 100, plugged: true, adapterW: 40, systemW: 40,
                      hasConnectedUSBDevice: true, systemChargingState: .full)
    }

    private func fixture() -> (PowerFlowView, NSWindow) {
        let window = NSWindow(contentRect: bounds, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let flow = PowerFlowView()
        window.contentView = flow
        flow.frame = bounds
        flow.layoutSubtreeIfNeeded()
        flow.update(snapshot: pending(), animated: false)
        flow.setAnimationsEnabled(true)
        return (flow, window)
    }

    private func pathPoints(_ path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            let count: Int
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            points.append(contentsOf: (0..<count).map { element.pointee.points[$0] })
        }
        return points
    }

    private func animationCount(_ glow: USBConnectionGlow) -> Int {
        var visited = Set<ObjectIdentifier>()
        func count(_ layer: CALayer?) -> Int {
            guard let layer, visited.insert(ObjectIdentifier(layer)).inserted else { return 0 }
            return (layer.animationKeys()?.count ?? 0) + count(layer.mask)
                + (layer.sublayers ?? []).reduce(0) { $0 + count($1) }
        }
        return count(glow.container)
    }

    private func assertStopped(_ glow: USBConnectionGlow,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(glow.container.isHidden, file: file, line: line)
        XCTAssertEqual(glow.container.opacity, 0, file: file, line: line)
        XCTAssertEqual(animationCount(glow), 0, file: file, line: line)
        XCTAssertNil(glow.phaseForTest(at: CACurrentMediaTime()), file: file, line: line)
    }

    private func assertWaitingBranchFollowsCurrentDeviceEdge(_ scene: PowerFlowScene, _ context: String = "",
                                                            file: StaticString = #filePath, line: UInt = #line) throws {
        let waiting = try XCTUnwrap(scene.idleDevice, context, file: file, line: line)
        let device = scene.edges[FlowEdgeRole.deviceOutput.rawValue].geometry
        XCTAssertEqual(waiting.start.x, max(58.5, device.start.x), context, file: file, line: line)
        XCTAssertEqual(waiting.start.y, device.start.y, context, file: file, line: line)
        XCTAssertEqual(waiting.control1, device.control1, context, file: file, line: line)
        XCTAssertEqual(waiting.control2, device.control2, context, file: file, line: line)
        XCTAssertEqual(waiting.end, CGPoint(x: scene.nodes[3].x - 18.5, y: device.end.y),
                       context, file: file, line: line)
        XCTAssertGreaterThanOrEqual(waiting.start.x, 58.5, context, file: file, line: line)
    }

    func testApprovedGlowUsesSoftFiniteSegmentOnTheCurveOutsideBothIconWells() throws {
        let geometry = try XCTUnwrap(PowerFlowScene.make(snapshot: pending()).idleDevice)
        let glow = USBConnectionGlow()
        defer { glow.stop() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try XCTUnwrap(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
                glow.configure(geometry: geometry, color: PopoverStyle.blue,
                               bounds: bounds, opacity: 1, animated: true)
            }
            XCTAssertFalse(glow.container.isHidden)
            XCTAssertEqual(animationCount(glow), 2)
            XCTAssertEqual(glow.strokeMasksForTest.map(\.lineWidth), [5, 2])
            for mask in glow.strokeMasksForTest {
                XCTAssertEqual(pathPoints(try XCTUnwrap(mask.path)), pathPoints(geometry.path))
                XCTAssertEqual(mask.lineCap, .butt)
                XCTAssertNil(mask.fillColor)
            }
            let clip = try XCTUnwrap(glow.clipForTest.path)
            XCTAssertEqual(clip.boundingBoxOfPath.minX, geometry.start.x, accuracy: 0.001)
            XCTAssertEqual(clip.boundingBoxOfPath.maxX, geometry.end.x, accuracy: 0.001)
            XCTAssertFalse(clip.contains(CGPoint(x: geometry.start.x - 0.1, y: geometry.start.y)))
            XCTAssertFalse(clip.contains(CGPoint(x: geometry.end.x + 0.1, y: geometry.end.y)))
            XCTAssertEqual(geometry.end.x, 269.5, accuracy: 0.001)

            for (light, peak) in zip(glow.lightLayersForTest, [CGFloat(0.06), 0.42]) {
                let colors = try XCTUnwrap(light.colors as? [CGColor])
                XCTAssertEqual(colors.count, 9)
                XCTAssertEqual(try XCTUnwrap(colors.first).alpha, 0)
                XCTAssertEqual(try XCTUnwrap(colors.last).alpha, 0)
                XCTAssertEqual(try XCTUnwrap(colors.map(\.alpha).max()), peak, accuracy: 0.0001)
                XCTAssertEqual(colors.map(\.alpha), Array(colors.reversed()).map(\.alpha))
                XCTAssertEqual(light.locations?[4].doubleValue, 0.5)
                let parent = try XCTUnwrap(light.superlayer)
                let width = light.convert(CGPoint(x: light.bounds.maxX, y: 0), to: glow.container).x
                    - light.convert(CGPoint(x: light.bounds.minX, y: 0), to: glow.container).x
                XCTAssertEqual(width, (geometry.end.x - geometry.start.x) * 0.28, accuracy: 0.001)
                let key = try XCTUnwrap(light.animationKeys()?.first)
                let travel = try XCTUnwrap(light.animation(forKey: key) as? CABasicAnimation)
                XCTAssertEqual(travel.duration, 3, accuracy: 0.001)
                XCTAssertEqual(travel.repeatCount, .infinity)
                XCTAssertEqual(travel.keyPath, "position.x")
                let start = try XCTUnwrap(travel.fromValue as? NSNumber).doubleValue
                let end = try XCTUnwrap(travel.toValue as? NSNumber).doubleValue
                XCTAssertEqual(parent.convert(CGPoint(x: start, y: 0), to: glow.container).x,
                               geometry.start.x - width / 2, accuracy: 0.001)
                XCTAssertEqual(parent.convert(CGPoint(x: end, y: 0), to: glow.container).x,
                               geometry.end.x + width / 2, accuracy: 0.001)
            }
        }
    }

    func testRendererKeepsOneClockAcrossGeometryColorBoundsAndOpacityUpdates() throws {
        let glow = USBConnectionGlow()
        defer { glow.stop() }
        let original = try XCTUnwrap(PowerFlowScene.make(snapshot: pending()).idleDevice)
        glow.configure(geometry: original, color: .systemBlue, bounds: bounds, opacity: 1, animated: true)
        let sampleTime = CACurrentMediaTime() + 0.7
        let phase = try XCTUnwrap(glow.phaseForTest(at: sampleTime))
        let installations = glow.animationInstallationsForTest
        let identities = glow.lightLayersForTest.map(ObjectIdentifier.init)
        var changed = original
        changed.start = CGPoint(x: 182, y: 90)
        changed.control1 = CGPoint(x: 217.5, y: 90)
        for (geometry, color, opacity) in [(original, NSColor.systemBlue, Float(1)),
                                          (changed, .systemGreen, 0.35), (original, .systemGray, 0.8)] {
            glow.configure(geometry: geometry, color: color,
                           bounds: bounds.insetBy(dx: -2, dy: 0), opacity: opacity, animated: true)
            XCTAssertEqual(try XCTUnwrap(glow.phaseForTest(at: sampleTime)), phase, accuracy: 0.000_001)
            XCTAssertEqual(glow.animationInstallationsForTest, installations)
            XCTAssertEqual(glow.lightLayersForTest.map(ObjectIdentifier.init), identities)
            XCTAssertEqual(animationCount(glow), 2)
            XCTAssertEqual(glow.container.opacity, opacity)
            XCTAssertEqual(pathPoints(try XCTUnwrap(glow.strokeMasksForTest.last?.path)), pathPoints(geometry.path))
        }
    }

    func testPendingRefreshKeepsClockAndOnlyTheDeviceConnectionGlows() throws {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil; window.close() }
        let glow = flow.connectionGlowForTest
        XCTAssertNotNil(flow.displayedSceneForTest.idleBattery)
        let device = try XCTUnwrap(flow.displayedSceneForTest.idleDevice)
        let battery = try XCTUnwrap(flow.displayedSceneForTest.idleBattery)
        XCTAssertNotEqual(device, battery)
        XCTAssertEqual(pathPoints(try XCTUnwrap(glow.strokeMasksForTest.last?.path)), pathPoints(device.path))
        let sampleTime = CACurrentMediaTime() + 0.7
        let phase = try XCTUnwrap(glow.phaseForTest(at: sampleTime))
        let installations = glow.animationInstallationsForTest
        var newer = pending()
        newer.adapterW = 41
        newer.systemW = 41
        for snapshot in [pending(), newer, newer] {
            flow.update(snapshot: snapshot, animated: true)
            flow.needsLayout = true
            flow.layoutSubtreeIfNeeded()
            flow.setAnimationsEnabled(true)
            XCTAssertFalse(flow.transitionIsAnimatingForTest)
            XCTAssertEqual(try XCTUnwrap(glow.phaseForTest(at: sampleTime)), phase, accuracy: 0.000_001)
            XCTAssertEqual(glow.animationInstallationsForTest, installations)
            XCTAssertEqual(animationCount(glow), 2)
        }
        newer.hasConnectedUSBDevice = false
        flow.update(snapshot: newer, animated: false)
        XCTAssertNotNil(flow.displayedSceneForTest.idleBattery)
        XCTAssertNil(flow.displayedSceneForTest.idleDevice)
        assertStopped(glow)
    }

    func testMeasuredAndDisconnectedTargetsFadeGlowWithTheDashedConnection() throws {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil; window.close() }
        let glow = flow.connectionGlowForTest
        for measured in [true, false] {
            flow.update(snapshot: pending(), animated: false)
            var target = pending()
            if measured { target.deviceOutputW = 7.5 } else { target.hasConnectedUSBDevice = false }
            let sampleTime = CACurrentMediaTime() + 0.7
            let phase = try XCTUnwrap(glow.phaseForTest(at: sampleTime))
            let installations = glow.animationInstallationsForTest
            flow.update(snapshot: target, animated: true)
            XCTAssertTrue(flow.transitionIsAnimatingForTest)
            var previous: Float = 1
            let visibleProgress: [CGFloat] = measured ? [0.25, 0.5, 0.75] : [0.1, 0.2, 0.3]
            for progress in visibleProgress {
                flow.advanceTransitionForTest(progress: progress)
                XCTAssertFalse(glow.container.isHidden)
                XCTAssertEqual(glow.container.opacity, flow.idleOpacitiesForTest[1], accuracy: 0.000_001)
                XCTAssertGreaterThan(glow.container.opacity, 0)
                XCTAssertLessThan(glow.container.opacity, previous)
                XCTAssertEqual(try XCTUnwrap(glow.phaseForTest(at: sampleTime)), phase, accuracy: 0.000_001)
                XCTAssertEqual(glow.animationInstallationsForTest, installations)
                previous = glow.container.opacity
            }
            if !measured {
                for progress: CGFloat in [0.35, 0.5, 0.9] {
                    flow.advanceTransitionForTest(progress: progress)
                    XCTAssertEqual(flow.idleOpacitiesForTest[1], 0)
                    XCTAssertEqual(flow.semanticNodeAlphasForTest[3], 0)
                    assertStopped(glow)
                }
            }
            flow.advanceTransitionForTest(progress: 1)
            assertStopped(glow)
        }
    }

    func testRapidReversalRetainsTheCurrentFadeAndLightPhase() throws {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil; window.close() }
        let glow = flow.connectionGlowForTest
        for measured in [true, false] {
            flow.update(snapshot: pending(), animated: false)
            var target = pending()
            if measured { target.deviceOutputW = 7.5 } else { target.hasConnectedUSBDevice = false }
            flow.update(snapshot: target, animated: true)
            flow.advanceTransitionForTest(progress: measured ? 0.4 : 0.2)
            let opacity = glow.container.opacity
            XCTAssertGreaterThan(opacity, 0)
            XCTAssertLessThan(opacity, 1)
            let sampleTime = CACurrentMediaTime() + 0.7
            let phase = try XCTUnwrap(glow.phaseForTest(at: sampleTime))
            let installations = glow.animationInstallationsForTest
            flow.update(snapshot: pending(), animated: true)
            flow.advanceTransitionForTest(progress: 0)
            XCTAssertEqual(glow.container.opacity, opacity, accuracy: 0.000_001)
            XCTAssertEqual(try XCTUnwrap(glow.phaseForTest(at: sampleTime)), phase, accuracy: 0.000_001)
            flow.advanceTransitionForTest(progress: 0.7)
            XCTAssertGreaterThan(glow.container.opacity, opacity)
            XCTAssertLessThan(glow.container.opacity, 1)
            flow.advanceTransitionForTest(progress: 1)
            XCTAssertEqual(glow.container.opacity, 1)
            XCTAssertFalse(glow.container.isHidden)
            XCTAssertEqual(try XCTUnwrap(glow.phaseForTest(at: sampleTime)), phase, accuracy: 0.000_001)
            XCTAssertEqual(glow.animationInstallationsForTest, installations)
        }
    }

    func testUSBDisconnectionRetiresTheHintWithItsNodeAcrossSupplyStatesAndCanReenter() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil; window.close() }
        let sources = [
            pending(),
            PowerSnapshot(percent: 70, plugged: true, adapterW: 68,
                          batteryW: 22.2, systemW: 45.8, hasConnectedUSBDevice: true),
            PowerSnapshot(percent: 70, batteryW: -39.7, systemW: 39.7,
                          hasConnectedUSBDevice: true),
            PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                          batteryW: -9.7, systemW: 39.7, hasConnectedUSBDevice: true),
        ]
        let glow = flow.connectionGlowForTest
        for source in sources {
            flow.update(snapshot: source, animated: false)
            let installations = glow.animationInstallationsForTest
            var disconnected = source
            disconnected.hasConnectedUSBDevice = false
            flow.update(snapshot: disconnected, animated: true)
            flow.advanceTransitionForTest(progress: 0.2)
            XCTAssertGreaterThan(flow.semanticNodeAlphasForTest[3], 0)
            XCTAssertGreaterThan(flow.idleOpacitiesForTest[1], 0)
            XCTAssertGreaterThan(glow.container.opacity, 0)
            for progress: CGFloat in [0.35, 0.55, 0.9, 1] {
                flow.advanceTransitionForTest(progress: progress)
                XCTAssertEqual(flow.semanticNodeAlphasForTest[3], 0)
                XCTAssertEqual(flow.idleOpacitiesForTest[1], 0,
                               "A disconnected USB hint must not float after its destination is gone")
                assertStopped(glow)
            }
            XCTAssertEqual(glow.animationInstallationsForTest, installations)
            flow.update(snapshot: source, animated: true)
            flow.advanceTransitionForTest(progress: 0.9)
            XCTAssertGreaterThan(flow.semanticNodeAlphasForTest[3], 0)
            XCTAssertGreaterThan(glow.container.opacity, 0)
            XCTAssertEqual(animationCount(glow), 2)
            XCTAssertEqual(glow.animationInstallationsForTest, installations + 2)
            flow.advanceTransitionForTest(progress: 1)
        }
    }

    func testPendingTopologyAndAppearanceChangesKeepTheExistingClock() throws {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil; window.close() }
        let glow = flow.connectionGlowForTest
        let original = flow.displayedSceneForTest.idleDevice
        let sampleTime = CACurrentMediaTime() + 0.7
        let phase = try XCTUnwrap(glow.phaseForTest(at: sampleTime))
        let installations = glow.animationInstallationsForTest
        let mixed = PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                                  batteryW: -9.7, systemW: 39.7, hasConnectedUSBDevice: true)
        flow.update(snapshot: mixed, animated: true)
        flow.advanceTransitionForTest(progress: 0.5)
        let middle = try XCTUnwrap(flow.displayedSceneForTest.idleDevice)
        XCTAssertNotEqual(middle, original)
        XCTAssertEqual(pathPoints(try XCTUnwrap(glow.strokeMasksForTest.last?.path)), pathPoints(middle.path))
        flow.advanceTransitionForTest(progress: 1)
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            flow.appearance = NSAppearance(named: appearance)
            flow.frame.size.width += 1
            flow.needsLayout = true
            flow.layoutSubtreeIfNeeded()
            flow.update(snapshot: mixed, animated: false)
            XCTAssertEqual(try XCTUnwrap(glow.phaseForTest(at: sampleTime)), phase, accuracy: 0.000_001)
            XCTAssertEqual(glow.animationInstallationsForTest, installations)
            XCTAssertEqual(animationCount(glow), 2)
        }
    }

    func testPendingCurveDoesNotJumpAtTransitionBoundariesOrRapidReversal() throws {
        let sources = [
            pending(),
            PowerSnapshot(percent: 70, plugged: true, adapterW: 68,
                          batteryW: 22.2, systemW: 45.8, hasConnectedUSBDevice: true),
            PowerSnapshot(percent: 70, batteryW: -39.7, systemW: 39.7,
                          hasConnectedUSBDevice: true),
            PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                          batteryW: -9.7, systemW: 39.7, hasConnectedUSBDevice: true),
        ]
        func nearby(_ a: PipeGeometry?, _ b: PipeGeometry?, _ context: String) throws {
            let before = try XCTUnwrap(a, context)
            let after = try XCTUnwrap(b, context)
            for (first, next) in zip([before.start, before.control1, before.control2, before.end],
                                     [after.start, after.control1, after.control2, after.end]) {
                XCTAssertLessThan(hypot(first.x - next.x, first.y - next.y), 1, context)
            }
        }
        for source in sources {
            let from = PowerFlowScene.make(snapshot: source)
            for measured in [true, false] {
                var target = source
                if measured { target.deviceOutputW = 7.5 } else { target.hasConnectedUSBDevice = false }
                let to = PowerFlowScene.make(snapshot: target)
                try nearby(from.idleDevice,
                           PowerFlowMorph.scene(from: from, to: to, progress: 0.001).idleDevice,
                           "The first departing frame must retain the approved branch origin and tangent")
                let interrupted = PowerFlowMorph.scene(from: from, to: to, progress: 0.4)
                try nearby(interrupted.idleDevice,
                           PowerFlowMorph.scene(from: interrupted, to: from, progress: 0.001).idleDevice,
                           "Reversing a fading connection must not reset its curve")
                try nearby(PowerFlowMorph.scene(from: interrupted, to: from, progress: 0.999).idleDevice,
                           from.idleDevice, "The returning connection must converge before its final frame")
                try nearby(PowerFlowMorph.scene(from: to, to: from, progress: 0.999).idleDevice,
                           from.idleDevice, "The arriving connection must not snap at completion")
            }
        }
    }

    func testPendingCurveFollowsTheRepackedDeviceOutletThroughoutEverySupplyTransition() throws {
        let snapshots = [
            pending(),
            PowerSnapshot(percent: 70, plugged: true, adapterW: 68,
                          batteryW: 22.2, systemW: 45.8, hasConnectedUSBDevice: true),
            PowerSnapshot(percent: 70, batteryW: -39.7, systemW: 39.7,
                          hasConnectedUSBDevice: true),
            PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                          batteryW: -9.7, systemW: 39.7, hasConnectedUSBDevice: true),
        ]
        let scenes = snapshots.map { PowerFlowScene.make(snapshot: $0) }
        for (source, from) in scenes.enumerated() {
            for (target, to) in scenes.enumerated() where source != target {
                for progress: CGFloat in [0.1, 0.25, 0.4, 0.55, 0.7, 0.9] {
                    let scene = PowerFlowMorph.scene(from: from, to: to, progress: progress)
                    try assertWaitingBranchFollowsCurrentDeviceEdge(scene, "\(from.layout) → \(to.layout) at \(progress)")
                }
            }
        }
    }

    func testNumericRetargetPreservesPendingCurvePhaseAndOriginalDeadline() throws {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil; window.close() }
        let charging = PowerSnapshot(percent: 70, plugged: true, adapterW: 68,
            batteryW: 22.2, systemW: 45.8, hasConnectedUSBDevice: true)
        flow.update(snapshot: charging, animated: false)
        var mixed = PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
            batteryW: -9.7, systemW: 39.7, hasConnectedUSBDevice: true)
        flow.update(snapshot: mixed, animated: true)
        flow.advanceTransitionForTest(progress: 0.4)
        let before = try XCTUnwrap(flow.displayedSceneForTest.idleDevice)
        try assertWaitingBranchFollowsCurrentDeviceEdge(flow.displayedSceneForTest)
        let deadline = try XCTUnwrap(flow.transitionDeadlineForTest)
        let glow = flow.connectionGlowForTest
        let sampleTime = CACurrentMediaTime() + 0.7
        let phase = try XCTUnwrap(glow.phaseForTest(at: sampleTime))
        let installations = glow.animationInstallationsForTest
        mixed.adapterW = 60
        mixed.batteryW = -30
        mixed.systemW = 90
        flow.update(snapshot: mixed, animated: true)
        flow.advanceTransitionForTest(progress: 0.4)
        XCTAssertEqual(flow.displayedSceneForTest.idleDevice, before,
                       "A power refresh must retain the displayed dashed curve, including its tangent")
        try assertWaitingBranchFollowsCurrentDeviceEdge(flow.displayedSceneForTest)
        XCTAssertEqual(pathPoints(try XCTUnwrap(glow.strokeMasksForTest.last?.path)), pathPoints(before.path))
        XCTAssertEqual(try XCTUnwrap(flow.transitionDeadlineForTest), deadline, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(glow.phaseForTest(at: sampleTime)), phase, accuracy: 0.000_001)
        flow.advanceTransitionForTest(progress: 0.6)
        XCTAssertNotEqual(flow.displayedSceneForTest.idleDevice, before)
        try assertWaitingBranchFollowsCurrentDeviceEdge(flow.displayedSceneForTest)
        flow.advanceTransitionForTest(progress: 1)
        XCTAssertEqual(flow.displayedSceneForTest.idleDevice, PowerFlowScene.make(snapshot: mixed).idleDevice)
        try assertWaitingBranchFollowsCurrentDeviceEdge(flow.displayedSceneForTest)
        XCTAssertEqual(try XCTUnwrap(glow.phaseForTest(at: sampleTime)), phase, accuracy: 0.000_001)
        XCTAssertEqual(glow.animationInstallationsForTest, installations)
        XCTAssertFalse(flow.transitionIsAnimatingForTest)
    }

    func testAnimationPolicyHideAndDetachStopTheGlowUntilTheViewIsActiveAgain() {
        for reason in ["motion disabled", "hidden", "detached"] {
            let (flow, window) = fixture()
            defer { flow.setAnimationsEnabled(false); window.contentView = nil; window.close() }
            let glow = flow.connectionGlowForTest
            XCTAssertEqual(animationCount(glow), 2, reason)
            let installations = glow.animationInstallationsForTest
            switch reason {
            case "motion disabled": flow.setAnimationsEnabled(false)
            case "hidden": flow.isHidden = true
            default: window.contentView = nil
            }
            assertStopped(glow)
            flow.update(snapshot: pending(), animated: true)
            flow.needsLayout = true
            flow.layoutSubtreeIfNeeded()
            assertStopped(glow)
            XCTAssertEqual(glow.animationInstallationsForTest, installations, reason)
            switch reason {
            case "motion disabled": flow.setAnimationsEnabled(true)
            case "hidden": flow.isHidden = false
            default: window.contentView = flow
            }
            XCTAssertFalse(glow.container.isHidden, reason)
            XCTAssertEqual(animationCount(glow), 2, reason)
        }
    }
}
