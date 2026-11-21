import AppKit
import XCTest
@testable import Wattson

final class PowerFlowTransitionTests: XCTestCase {
    private func fixture() -> (PowerFlowView, NSWindow) {
        _ = NSApplication.shared
        let frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                           height: PowerFlowView.preferredHeight)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let flow = PowerFlowView()
        window.contentView = flow
        flow.frame = frame
        flow.layoutSubtreeIfNeeded()
        flow.update(snapshot: battery(), animated: false)
        flow.setAnimationsEnabled(true)
        return (flow, window)
    }

    private func battery() -> PowerSnapshot {
        PowerSnapshot(percent: 70, batteryW: -39.7, systemW: 39.7)
    }

    private func charging() -> PowerSnapshot {
        PowerSnapshot(percent: 70, plugged: true, adapterW: 68,
                      batteryW: 22.2, systemW: 45.8)
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.001, file: file, line: line)
    }

    private func assertRenderedNodes(_ view: PowerFlowView,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let scene = view.displayedSceneForTest
        let frames = view.semanticNodeFramesForTest
        XCTAssertEqual(frames.count, 4, file: file, line: line)
        for (frame, point) in zip(frames, scene.nodes) {
            assertPoint(CGPoint(x: frame.midX, y: frame.minY + FlowNodeView.boxSize / 2),
                        point, file: file, line: line)
        }
        XCTAssertEqual(view.transitionOverlayCountForTest, 0, file: file, line: line)
        XCTAssertEqual(view.transitionTargetOpacityForTest, 1, file: file, line: line)
    }

    private func activeAnimationKeys(in view: NSView) -> [String] {
        var visited = Set<ObjectIdentifier>()
        var keys: [String] = []
        func visit(_ layer: CALayer?) {
            guard let layer, visited.insert(ObjectIdentifier(layer)).inserted else { return }
            keys.append(contentsOf: layer.animationKeys() ?? [])
            visit(layer.mask)
            (layer.sublayers ?? []).forEach(visit)
        }
        func visitView(_ view: NSView) {
            visit(view.layer)
            view.subviews.forEach(visitView)
        }
        visitView(view)
        return keys
    }

    private func assertConnected(_ scene: PowerFlowScene,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let inputs: [(FlowEdgeRole, Int)] = [(.adapterInput, 0), (.batteryInput, 1)]
        let outputs: [(FlowEdgeRole, Int)] = [(.systemOutput, 2), (.batteryCharge, 1), (.deviceOutput, 3)]
        for (role, node) in inputs {
            let edge = scene.edges[role.rawValue]
            guard max(edge.startWidth, edge.endWidth) > 0.5, !edge.isCollapsed else { continue }
            assertPoint(edge.geometry.start,
                        CGPoint(x: scene.nodes[node].x + 13, y: scene.nodes[node].y), file: file, line: line)
            XCTAssertEqual(edge.geometry.end.x, scene.jointStart.x, accuracy: 0.001, file: file, line: line)
            XCTAssertLessThanOrEqual(edge.geometry.start.x, edge.geometry.end.x, file: file, line: line)
        }
        for (role, node) in outputs {
            let edge = scene.edges[role.rawValue]
            guard max(edge.startWidth, edge.endWidth) > 0.5, !edge.isCollapsed else { continue }
            assertPoint(edge.geometry.end,
                        CGPoint(x: scene.nodes[node].x - 13, y: scene.nodes[node].y), file: file, line: line)
            XCTAssertEqual(edge.geometry.start.x, scene.jointEnd.x, accuracy: 0.001, file: file, line: line)
            XCTAssertLessThanOrEqual(edge.geometry.start.x, edge.geometry.end.x, file: file, line: line)
        }
        let common = scene.edges[FlowEdgeRole.common.rawValue]
        assertPoint(common.geometry.start, scene.jointStart, file: file, line: line)
        assertPoint(common.geometry.end, scene.jointEnd, file: file, line: line)
        for edge in scene.edges {
            XCTAssertTrue([edge.startWidth, edge.endWidth, edge.verticalTaper,
                edge.geometry.start.x, edge.geometry.start.y,
                edge.geometry.control1.x, edge.geometry.control1.y,
                edge.geometry.control2.x, edge.geometry.control2.y,
                edge.geometry.end.x, edge.geometry.end.y].allSatisfy(\.isFinite), file: file, line: line)
            XCTAssertGreaterThanOrEqual(edge.startWidth, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(edge.endWidth, 0, file: file, line: line)
        }
    }

    func testUSBAdditionMovesActualNodesAndDeformsConnectedPipesAtMidpoint() throws {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        let before = flow.displayedSceneForTest
        var pending = battery()
        pending.hasConnectedUSBDevice = true
        let target = PowerFlowScene.make(snapshot: pending)
        flow.update(snapshot: pending, animated: true)
        XCTAssertTrue(flow.transitionIsAnimatingForTest)
        XCTAssertEqual(try XCTUnwrap(flow.transitionDurationForTest), 0.32, accuracy: 0.001)
        flow.advanceTransitionForTest(progress: 0.5)
        let middle = flow.displayedSceneForTest
        XCTAssertGreaterThan(middle.nodes[2].y, target.nodes[2].y)
        XCTAssertLessThan(middle.nodes[2].y, before.nodes[2].y)
        XCTAssertNotEqual(middle.edges, before.edges)
        XCTAssertNotEqual(middle.edges, target.edges)
        assertRenderedNodes(flow)
        assertConnected(middle)
        XCTAssertTrue(flow.nodePresentationsForTest.contains {
            $0.caption == "USB Device" && $0.value == "Connected"
        })
        XCTAssertEqual(middle.edges[FlowEdgeRole.deviceOutput.rawValue].endWidth, 0,
                       "A connection hint must not grow a powered output")
        flow.advanceTransitionForTest(progress: 1)
        XCTAssertFalse(flow.transitionIsAnimatingForTest)
        XCTAssertEqual(flow.displayedSceneForTest.nodes, target.nodes)
        XCTAssertEqual(flow.displayedSceneForTest.edges, target.edges)
        assertRenderedNodes(flow)
    }

    func testMeasuredUSBBranchGrowsWithoutReplacingTheWholeDiagram() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        var pending = charging()
        pending.hasConnectedUSBDevice = true
        flow.update(snapshot: pending, animated: false)
        var measured = pending
        measured.deviceOutputW = 7.5
        let target = PowerFlowScene.make(snapshot: measured)
        flow.update(snapshot: measured, animated: true)
        flow.advanceTransitionForTest(progress: 0.5)
        let width = flow.displayedSceneForTest.edges[FlowEdgeRole.deviceOutput.rawValue].endWidth
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThan(width, target.edges[FlowEdgeRole.deviceOutput.rawValue].endWidth)
        assertRenderedNodes(flow)
        assertConnected(flow.displayedSceneForTest)
        XCTAssertTrue(flow.nodePresentationsForTest.contains {
            $0.caption == "Device Output" && $0.value == "7.5 W"
        })
    }

    func testBatteryRoleReversalKeepsOneBatteryAndConnectedForwardPaths() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        var source = charging()
        source.deviceOutputW = 7.5
        var target = battery()
        target.deviceOutputW = 7.5
        for (from, to) in [(source, target), (target, source)] {
            flow.update(snapshot: from, animated: false)
            flow.update(snapshot: to, animated: true)
            for progress in [CGFloat(0.1), 0.25, 0.5, 0.75, 0.9] {
                flow.advanceTransitionForTest(progress: progress)
                assertConnected(flow.displayedSceneForTest)
                assertRenderedNodes(flow)
                let frames = flow.semanticNodeFramesForTest
                XCTAssertLessThanOrEqual(frames[1].maxY, PowerFlowView.preferredHeight)
                XCTAssertFalse(frames[1].insetBy(dx: 28, dy: 0)
                    .intersects(frames[3].insetBy(dx: 28, dy: 0)),
                    "Battery and USB must not occupy the same icon column while crossing")
            }
            flow.advanceTransitionForTest(progress: 1)
            XCTAssertEqual(flow.displayedSceneForTest.nodes, PowerFlowScene.make(snapshot: to).nodes)
        }
    }

    func testBatteryToAdapterSplitKeepsCrossingLabelsAndArrivingAdapterSeparate() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        var source = battery()
        source.deviceOutputW = 7.5
        var target = charging()
        target.deviceOutputW = 7.5
        flow.update(snapshot: source, animated: false)
        XCTAssertEqual(flow.semanticNodeAlphasForTest[0], 0)
        flow.update(snapshot: target, animated: true)
        for progress in [CGFloat(0.1), 0.25, 0.4, 0.5, 0.6, 0.75, 0.9] {
            flow.advanceTransitionForTest(progress: progress)
            let nodes = flow.semanticNodeAlphasForTest
            let labels = flow.semanticNodeLabelAlphasForTest
            if progress <= 0.6 {
                XCTAssertEqual(nodes[0], 0,
                               "The incoming Adapter must not appear over the departing Battery column")
            } else if progress < 0.85 {
                XCTAssertGreaterThan(nodes[0], 0)
                XCTAssertLessThan(nodes[0], 1)
            } else {
                XCTAssertEqual(nodes[0], 1)
            }
            XCTAssertEqual(nodes[1], 1, "The Battery icon must remain visible throughout its journey")
            XCTAssertEqual(nodes[2], 1, "System remains a persistent destination")
            XCTAssertEqual(nodes[3], 1, "USB remains a persistent destination")
            if progress >= 0.2 && progress <= 0.6 {
                XCTAssertEqual(labels[1], 0,
                               "Moving Battery text must clear the diagram while the icon crosses")
            } else if progress < 0.85 {
                XCTAssertGreaterThan(labels[1], 0)
                XCTAssertLessThan(labels[1], 1, "Battery text must fade out and back in instead of snapping")
            } else {
                XCTAssertEqual(labels[1], 1)
            }
            assertRenderedNodes(flow)
        }
        flow.advanceTransitionForTest(progress: 1)
        XCTAssertEqual(flow.semanticNodeAlphasForTest, [1, 1, 1, 1])
        XCTAssertEqual(flow.semanticNodeLabelAlphasForTest, [1, 1, 1, 1])
        XCTAssertEqual(flow.nodePresentationsForTest.map(\.caption),
                       ["Adapter", "To Battery", "Mac Load", "Device Output"])
    }

    func testBatteryBranchAndCaptionAreAdmittedBeforeCompletionInBothDirections() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        var charger = charging()
        charger.deviceOutputW = 7.5
        let mixed = PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                                  batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2)
        for (from, to) in [(charger, mixed), (mixed, charger)] {
            flow.update(snapshot: from, animated: false)
            flow.update(snapshot: to, animated: true)
            for progress: CGFloat in [0.2, 0.4, 0.6] {
                flow.advanceTransitionForTest(progress: progress)
                XCTAssertEqual(flow.semanticNodeLabelAlphasForTest[1], 0)
            }
            flow.advanceTransitionForTest(progress: 0.75)
            XCTAssertGreaterThan(flow.semanticNodeLabelAlphasForTest[1], 0.5)
            XCTAssertLessThan(flow.semanticNodeLabelAlphasForTest[1], 1)
            let target = PowerFlowScene.make(snapshot: to)
            let role: FlowEdgeRole = target.nodes[1].x == 40 ? .batteryInput : .batteryCharge
            for progress: CGFloat in [0.85, 0.9, 0.95, 0.999] {
                flow.advanceTransitionForTest(progress: progress)
                XCTAssertTrue(flow.transitionIsAnimatingForTest, "Admission must complete before timer handoff")
                XCTAssertEqual(flow.semanticNodeLabelAlphasForTest[1], 1)
                let branch = flow.displayedSceneForTest.edges[role.rawValue]
                let wanted = target.edges[role.rawValue]
                XCTAssertGreaterThanOrEqual(branch.startWidth, wanted.startWidth * 0.8)
                XCTAssertGreaterThanOrEqual(branch.endWidth, wanted.endWidth * 0.8)
                assertConnected(flow.displayedSceneForTest)
            }
            flow.advanceTransitionForTest(progress: 1)
            XCTAssertEqual(flow.displayedSceneForTest.edges, target.edges)
        }
    }

    func testNewNodesAndIdleBatteryDashFinishTheirRevealBeforeTheDeadline() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        var batteryUSB = battery()
        batteryUSB.deviceOutputW = 12.2
        let idleUSB = PowerSnapshot(percent: 99, plugged: true, adapterW: 52,
                                    systemW: 52, deviceOutputW: 7.5, systemChargingState: .full)
        flow.update(snapshot: batteryUSB, animated: false)
        flow.update(snapshot: idleUSB, animated: true)
        flow.advanceTransitionForTest(progress: 0.6)
        XCTAssertEqual(flow.idleOpacitiesForTest[0], 0)
        for progress: CGFloat in [0.85, 0.9, 0.999] {
            flow.advanceTransitionForTest(progress: progress)
            XCTAssertEqual(flow.semanticNodeAlphasForTest[0], 1)
            XCTAssertEqual(flow.semanticNodeLabelAlphasForTest[1], 1)
            XCTAssertEqual(flow.idleOpacitiesForTest[0], 1)
        }
        flow.advanceTransitionForTest(progress: 1)
        flow.update(snapshot: batteryUSB, animated: true)
        flow.advanceTransitionForTest(progress: 0.2)
        XCTAssertEqual(flow.idleOpacitiesForTest[0], 0)
        flow.advanceTransitionForTest(progress: 1)
        flow.update(snapshot: battery(), animated: false)
        flow.update(snapshot: batteryUSB, animated: true)
        for progress: CGFloat in [0.85, 0.9, 0.999] {
            flow.advanceTransitionForTest(progress: progress)
            XCTAssertEqual(flow.semanticNodeAlphasForTest[3], 1)
        }
    }

    func testInterruptedTransitionStartsAtTheCurrentlyDisplayedGeometry() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        flow.update(snapshot: charging(), animated: true)
        flow.advanceTransitionForTest(progress: 0.43)
        let interrupted = flow.displayedSceneForTest
        var target = battery()
        target.hasConnectedUSBDevice = true
        flow.update(snapshot: target, animated: true)
        flow.advanceTransitionForTest(progress: 0)
        XCTAssertEqual(flow.displayedSceneForTest.nodes, interrupted.nodes)
        XCTAssertEqual(flow.displayedSceneForTest.edges, interrupted.edges)
        assertRenderedNodes(flow)
        flow.advanceTransitionForTest(progress: 0.5)
        XCTAssertNotEqual(flow.displayedSceneForTest.nodes, interrupted.nodes)
        assertConnected(flow.displayedSceneForTest)
        flow.advanceTransitionForTest(progress: 1)
        XCTAssertEqual(flow.displayedSceneForTest.edges, PowerFlowScene.make(snapshot: target).edges)
    }

    func testInterruptedThreeWayLayoutPreservesCurrentCompactSpacingAndHeight() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        var threeWay = charging()
        threeWay.deviceOutputW = 7.5
        var batteryUSB = battery()
        batteryUSB.deviceOutputW = 7.5
        let mixedUSB = PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                                     batteryW: -9.7, systemW: 39.7, deviceOutputW: 7.5)
        for target in [batteryUSB, mixedUSB] {
            flow.update(snapshot: charging(), animated: false)
            flow.update(snapshot: threeWay, animated: true)
            flow.advanceTransitionForTest(progress: 0.4)
            let currentFrames = flow.semanticNodeFramesForTest
            let currentSpacing = flow.semanticNodeCompactFractionsForTest
            for index in 1...3 {
                XCTAssertGreaterThan(currentSpacing[index], 0)
                XCTAssertLessThan(currentSpacing[index], 1)
                XCTAssertGreaterThan(currentFrames[index].height, 68)
                XCTAssertLessThan(currentFrames[index].height, 74)
            }
            flow.update(snapshot: target, animated: true)
            flow.advanceTransitionForTest(progress: 0)
            XCTAssertEqual(flow.semanticNodeFramesForTest, currentFrames,
                           "Retargeting must preserve both position and the current stack height")
            XCTAssertEqual(flow.semanticNodeCompactFractionsForTest, currentSpacing,
                           "Label spacing must continue from its displayed fraction, not a compact Boolean")
            flow.advanceTransitionForTest(progress: 0.5)
            for index in 1...3 {
                XCTAssertLessThanOrEqual(flow.semanticNodeCompactFractionsForTest[index], currentSpacing[index],
                                         "Compact spacing may hold while the battery clears the column")
            }
            flow.advanceTransitionForTest(progress: 0.7)
            for index in 1...3 {
                XCTAssertGreaterThan(flow.semanticNodeCompactFractionsForTest[index], 0)
                XCTAssertLessThan(flow.semanticNodeCompactFractionsForTest[index], currentSpacing[index])
            }
            flow.advanceTransitionForTest(progress: 1)
            XCTAssertEqual(flow.semanticNodeCompactFractionsForTest, [0, 0, 0, 0])
            XCTAssertEqual(flow.semanticNodeFramesForTest.map(\.height), [74, 74, 74, 74],
                           "Settlement must restore normal spacing even when isCompact was already false")
        }
    }

    func testInterruptedUSBConnectionDashRetainsItsCurrentOpacity() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        var pending = charging()
        pending.hasConnectedUSBDevice = true
        var measured = pending
        measured.deviceOutputW = 7.5
        for (from, to) in [(measured, pending), (pending, measured)] {
            flow.update(snapshot: from, animated: false)
            flow.update(snapshot: to, animated: true)
            flow.advanceTransitionForTest(progress: 0.4)
            let interrupted = flow.idleOpacitiesForTest
            XCTAssertGreaterThan(interrupted[1], 0)
            XCTAssertLessThan(interrupted[1], 1)
            flow.update(snapshot: from, animated: true)
            flow.advanceTransitionForTest(progress: 0)
            XCTAssertEqual(flow.idleOpacitiesForTest, interrupted,
                           "An interrupted dashed connection must not flash fully visible")
            flow.advanceTransitionForTest(progress: 0.5)
            let settlesVisible = from.coherentDeviceOutputW == nil
            if settlesVisible {
                XCTAssertGreaterThan(flow.idleOpacitiesForTest[1], interrupted[1])
                XCTAssertLessThan(flow.idleOpacitiesForTest[1], 1)
            } else {
                XCTAssertLessThan(flow.idleOpacitiesForTest[1], interrupted[1])
                XCTAssertGreaterThan(flow.idleOpacitiesForTest[1], 0)
            }
            flow.advanceTransitionForTest(progress: 1)
            XCTAssertEqual(flow.idleOpacitiesForTest[1], settlesVisible ? 1 : 0)
        }
    }

    func testNumericRefreshLayoutAndDuplicateEnableDoNotRestartActiveMotion() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        flow.update(snapshot: charging(), animated: true)
        flow.advanceTransitionForTest(progress: 0.4)
        let installations = flow.transitionInstallationsForTest
        let middle = flow.displayedSceneForTest.nodes
        var newer = charging()
        newer.percent = 71
        newer.adapterW = 69
        newer.systemW = 46.8
        flow.update(snapshot: newer, animated: true)
        flow.needsLayout = true
        flow.layoutSubtreeIfNeeded()
        flow.setAnimationsEnabled(true)
        XCTAssertEqual(flow.transitionInstallationsForTest, installations)
        XCTAssertEqual(flow.displayedSceneForTest.nodes, middle)
        XCTAssertTrue(flow.transitionIsAnimatingForTest)
        XCTAssertTrue(flow.nodePresentationsForTest.contains { $0.caption == "Adapter" && $0.value == "69.0 W" })
        flow.advanceTransitionForTest(progress: 1)
        XCTAssertEqual(flow.displayedSceneForTest.edges, PowerFlowScene.make(snapshot: newer).edges)
    }

    func testNumericRetargetPreservesDisplayedEdgesAndTheOriginalDeadline() throws {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        flow.update(snapshot: charging(), animated: false)
        var target = charging()
        target.deviceOutputW = 7.5
        flow.update(snapshot: target, animated: true)
        flow.advanceTransitionForTest(progress: 0.4)
        let middle = flow.displayedSceneForTest
        let frames = flow.semanticNodeFramesForTest
        let deadline = try XCTUnwrap(flow.transitionDeadlineForTest)
        let installations = flow.transitionInstallationsForTest
        target.adapterW = 102
        target.batteryW = 10
        target.systemW = 92
        target.deviceOutputW = 22
        flow.update(snapshot: target, animated: true)
        flow.advanceTransitionForTest(progress: 0.4)
        XCTAssertEqual(flow.displayedSceneForTest.edges, middle.edges,
                       "A fresh numeric sample must not snap widths or control points toward its new target")
        XCTAssertEqual(flow.semanticNodeFramesForTest, frames)
        XCTAssertEqual(try XCTUnwrap(flow.transitionDeadlineForTest), deadline, accuracy: 0.000_001,
                       "Repeated readings must not extend the structural transition")
        XCTAssertEqual(flow.transitionInstallationsForTest, installations)
        flow.advanceTransitionForTest(progress: 0.5)
        XCTAssertNotEqual(flow.displayedSceneForTest.edges, middle.edges)
        assertConnected(flow.displayedSceneForTest)
        flow.advanceTransitionForTest(progress: 1)
        XCTAssertEqual(flow.displayedSceneForTest.edges, PowerFlowScene.make(snapshot: target).edges)
        XCTAssertFalse(flow.transitionIsAnimatingForTest)
    }

    func testNumericSamplesPreserveTheOriginalNodeMotionAndDoNotReanchorUnchangedValues() throws {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        var source = battery()
        source.deviceOutputW = 12.2
        var target = charging()
        target.deviceOutputW = 7.5
        flow.update(snapshot: source, animated: false)
        flow.update(snapshot: target, animated: true)
        let deadline = try XCTUnwrap(flow.transitionDeadlineForTest)
        let original = PowerFlowScene.make(snapshot: source)
        for (progress, watts) in [(CGFloat(0.35), 70.0), (0.55, 72), (0.9999, 74)] {
            flow.advanceTransitionForTest(progress: progress)
            let presented = flow.displayedSceneForTest
            target.adapterW = watts
            target.systemW = watts - target.batteryW
            flow.update(snapshot: target, animated: true)
            flow.advanceTransitionForTest(progress: progress)
            for (before, after) in zip(presented.edges, flow.displayedSceneForTest.edges) {
                assertPoint(after.geometry.start, before.geometry.start)
                assertPoint(after.geometry.control1, before.geometry.control1)
                assertPoint(after.geometry.control2, before.geometry.control2)
                assertPoint(after.geometry.end, before.geometry.end)
                XCTAssertEqual(after.startWidth, before.startWidth, accuracy: 0.000_001)
                XCTAssertEqual(after.endWidth, before.endWidth, accuracy: 0.000_001)
            }
            XCTAssertEqual(try XCTUnwrap(flow.transitionDeadlineForTest), deadline, accuracy: 0.000_001)
            let next = min(0.99999, progress + 0.05)
            flow.advanceTransitionForTest(progress: next)
            XCTAssertEqual(flow.displayedSceneForTest.nodes,
                           PowerFlowMorph.scene(from: original, to: PowerFlowScene.make(snapshot: target), progress: next).nodes,
                           "Numeric refreshes must not restart the battery's staging or smoothstep clock")
            assertConnected(flow.displayedSceneForTest)
            let anchor = flow.numericCorrectionProgressForTest
            flow.update(snapshot: target, animated: true)
            XCTAssertEqual(flow.numericCorrectionProgressForTest, anchor,
                           "An identical reading must not churn the remaining-width correction")
        }
        flow.advanceTransitionForTest(progress: 1)
        XCTAssertEqual(flow.displayedSceneForTest.edges, PowerFlowScene.make(snapshot: target).edges)
    }

    func testNumericZeroMacLoadKeepsCurrentNodeOpacityUntilItCanSettle() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        var target = charging()
        target.deviceOutputW = 7.5
        flow.update(snapshot: target, animated: true)
        flow.advanceTransitionForTest(progress: 0.7)
        let alpha = flow.semanticNodeAlphasForTest[2]
        target.deviceOutputW = target.systemW
        flow.update(snapshot: target, animated: true)
        flow.advanceTransitionForTest(progress: 0.7)
        XCTAssertEqual(flow.semanticNodeAlphasForTest[2], alpha, accuracy: 0.000_001)
        flow.advanceTransitionForTest(progress: 0.9)
        XCTAssertLessThan(flow.semanticNodeAlphasForTest[2], alpha)
        XCTAssertGreaterThan(flow.semanticNodeAlphasForTest[2], 0.6)
        assertConnected(flow.displayedSceneForTest)
        flow.advanceTransitionForTest(progress: 1)
        XCTAssertEqual(flow.semanticNodeAlphasForTest[2], 0.6, accuracy: 0.000_001)
    }

    func testSameMeaningStaticRefreshSettlesAnActiveTransitionImmediately() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        var target = charging()
        target.deviceOutputW = 7.5
        flow.update(snapshot: target, animated: true)
        flow.advanceTransitionForTest(progress: 0.4)
        XCTAssertTrue(flow.transitionIsAnimatingForTest)
        target.adapterW = 69
        target.systemW = 46.8
        flow.update(snapshot: target, animated: false)
        XCTAssertFalse(flow.transitionIsAnimatingForTest)
        XCTAssertNil(flow.transitionDeadlineForTest)
        XCTAssertEqual(flow.displayedSceneForTest.edges, PowerFlowScene.make(snapshot: target).edges)
        XCTAssertEqual(flow.semanticNodeLabelAlphasForTest, [1, 1, 1, 1])
    }

    func testMixedCompletionInstallsEachNativeHeadOnlyOnce() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        let target = PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                                   batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2)
        flow.update(snapshot: target, animated: true)
        flow.advanceTransitionForTest(progress: 0.9)
        let fusion = flow.fusionParticleLayerForTest
        let before = fusion.animationInstallationsForTest
        flow.advanceTransitionForTest(progress: 1)
        let heads = fusion.particleLayersForTest.count
        XCTAssertGreaterThan(heads, 0)
        XCTAssertEqual(fusion.animationInstallationsForTest - before, heads,
                       "Completion must install final phases once, without constructing a second native pool")
        XCTAssertFalse(flow.transitionIsAnimatingForTest)
        XCTAssertTrue(flow.fusionParticlesVisibleForTest)
        XCTAssertEqual(flow.displayedSceneForTest.edges, PowerFlowScene.make(snapshot: target).edges)
    }

    func testSharedSeamHandoffHasExactlyOneVisibleNativeOwner() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        let target = PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                                   batteryW: -9.7, systemW: 39.7, hasConnectedUSBDevice: true)
        let seams: [(CGFloat, FlowEdgeRole)] = [(-0.0009, .common), (0, .systemOutput), (0.0009, .systemOutput)]
        for (offset, owner) in seams {
            let now = CACurrentMediaTime()
            let seed = FlowMorphParticleSeed(route: .adapterSystem, ordinal: 98_765,
                phase: 0.5, epoch: now, pathLength: 250, wallPeriod: 2.4,
                offset: 0, radius: 1.5, color: NSColor.white.cgColor, shadowColor: NSColor.white.cgColor,
                shadowOpacity: 0.6, shadowRadius: 3, position: CGPoint(x: 182 + offset, y: 90), opacity: 0.61)
            flow.installParticleHandoffForTest(snapshot: target, seeds: [seed], now: now)
            XCTAssertEqual(flow.particleHandoffOwnersForTest(ordinal: seed.ordinal, now: now), [owner],
                           "A shared endpoint must not clone an ordinary head into two native pools")
            let visible = flow.particleLayersForTest.filter { $0.opacity > 0 }
            XCTAssertEqual(visible.count, 1)
            if let head = visible.first {
                assertPoint(head.position, seed.position)
                XCTAssertEqual(head.opacity, seed.opacity, accuracy: 0.000_001)
            }
        }
    }

    func testHiddenMixedTargetSettlesWithoutStartingPreparationAndReopensNormally() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        let target = PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                                   batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2)
        for detach in [false, true] {
            flow.update(snapshot: battery(), animated: false)
            flow.update(snapshot: target, animated: true)
            flow.advanceTransitionForTest(progress: 0.4)
            let fusion = flow.fusionParticleLayerForTest
            let preparations = fusion.preparationCountForTest
            let installations = fusion.animationInstallationsForTest
            if detach { window.contentView = nil } else { flow.isHidden = true }
            XCTAssertFalse(flow.transitionIsAnimatingForTest)
            XCTAssertEqual(flow.displayedSceneForTest.edges, PowerFlowScene.make(snapshot: target).edges)
            XCTAssertEqual(fusion.preparationCountForTest, preparations)
            XCTAssertEqual(fusion.animationInstallationsForTest, installations,
                           "A hidden target must not start native rides just to stop them immediately")
            XCTAssertFalse(fusion.pendingPreparationForTest)
            XCTAssertTrue(activeAnimationKeys(in: flow).isEmpty)
            var refresh = target
            refresh.adapterW = 31
            refresh.systemW = 40.7
            flow.update(snapshot: refresh, animated: true)
            flow.needsLayout = true
            flow.layoutSubtreeIfNeeded()
            flow.setAnimationsEnabled(true)
            XCTAssertFalse(flow.transitionIsAnimatingForTest)
            XCTAssertEqual(fusion.preparationCountForTest, preparations,
                           "Telemetry arriving after hide/detach must not restart preparation")
            XCTAssertTrue(activeAnimationKeys(in: flow).isEmpty)
            if detach { window.contentView = flow } else { flow.isHidden = false }
            XCTAssertTrue(flow.fusionParticlesVisibleForTest)
            XCTAssertGreaterThan(fusion.particleLayersForTest.count, 0)
            XCTAssertFalse(flow.transitionIsAnimatingForTest)
        }
    }

    func testDisablingMotionDuringMixedTransitionRetainsStaticHeads() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        let target = PowerSnapshot(percent: 70, plugged: true, adapterW: 30,
                                   batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2)
        flow.update(snapshot: target, animated: true)
        flow.advanceTransitionForTest(progress: 0.4)
        flow.setAnimationsEnabled(false)
        XCTAssertFalse(flow.transitionIsAnimatingForTest)
        XCTAssertTrue(flow.fusionParticlesVisibleForTest)
        XCTAssertGreaterThan(flow.fusionParticleLayerForTest.particleLayersForTest.count, 0)
        XCTAssertFalse(flow.fusionParticleLayerForTest.pendingPreparationForTest)
        XCTAssertTrue(activeAnimationKeys(in: flow).isEmpty)
    }

    func testAnimationPolicyHideDetachResizeAndAppearanceSettleToLatestTarget() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        func start() {
            flow.setAnimationsEnabled(true)
            flow.update(snapshot: battery(), animated: false)
            flow.update(snapshot: charging(), animated: true)
            flow.advanceTransitionForTest(progress: 0.4)
            XCTAssertTrue(flow.transitionIsAnimatingForTest)
        }
        func settled(_ reason: String) {
            XCTAssertEqual(flow.transitionOverlayCountForTest, 0, reason)
            XCTAssertFalse(flow.transitionIsAnimatingForTest, reason)
            XCTAssertEqual(flow.transitionTargetOpacityForTest, 1, reason)
            XCTAssertEqual(flow.displayedSceneForTest.nodes, PowerFlowScene.make(snapshot: charging()).nodes, reason)
            XCTAssertEqual(flow.displayedSceneForTest.edges, PowerFlowScene.make(snapshot: charging()).edges, reason)
        }
        start(); flow.setAnimationsEnabled(false); settled("animation policy")
        start(); flow.isHidden = true; settled("hide")
        let hiddenAnimations = activeAnimationKeys(in: flow)
        XCTAssertTrue(hiddenAnimations.isEmpty,
                      "Hiding a morph retained animations: \(hiddenAnimations)")
        flow.isHidden = false
        start()
        flow.appearance = NSAppearance(named: PopoverStyle.isDark(flow.effectiveAppearance) ? .aqua : .darkAqua)
        flow.update(snapshot: charging(), animated: false)
        settled("appearance")
        start(); flow.viewDidChangeBackingProperties(); settled("backing scale")
        start()
        flow.frame.size.width -= 1
        flow.needsLayout = true
        flow.layoutSubtreeIfNeeded()
        settled("resize")
        start(); window.contentView = nil; settled("detach")
        let detachedAnimations = activeAnimationKeys(in: flow)
        XCTAssertTrue(detachedAnimations.isEmpty,
                      "Detaching a morph retained animations: \(detachedAnimations)")
        flow.update(snapshot: battery(), animated: true)
        XCTAssertFalse(flow.transitionIsAnimatingForTest)
        XCTAssertEqual(flow.displayedSceneForTest.nodes, PowerFlowScene.make(snapshot: battery()).nodes)
    }

    func testContentControllerPreservesMorphDuringSamplesAndSettlesDegradedTelemetry() throws {
        _ = NSApplication.shared
        let suite = testDefaultsSuite("PowerFlowTransitionIntegration")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        Settings.configureForTest(defaults: defaults)
        defer {
            Settings.resetTestConfiguration()
            defaults.removePersistentTestDomain(forName: suite)
        }
        let content = PopoverContentViewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PopoverStyle.width, height: 850),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = content
        defer { content.setAnimationsEnabled(false); content.setPresentationActive(false); window.contentViewController = nil }
        content.setViewportHeight(850)
        content.update(snapshot: battery(), history: [], peak: 0, degraded: false)
        content.setPresentationActive(true)
        content.setAnimationsEnabled(true)
        let flow = try XCTUnwrap(content.moduleViewForTest(.flow) as? PowerFlowView)
        content.update(snapshot: charging(), history: [], peak: 0, degraded: false)
        XCTAssertTrue(flow.transitionIsAnimatingForTest)
        flow.advanceTransitionForTest(progress: 0.4)
        let count = flow.transitionInstallationsForTest
        content.update(snapshot: charging(), history: [], peak: 0, degraded: false)
        content.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(flow.transitionInstallationsForTest, count)
        XCTAssertTrue(flow.transitionIsAnimatingForTest)
        content.update(snapshot: battery(), history: [], peak: 0, degraded: true)
        XCTAssertFalse(flow.transitionIsAnimatingForTest)
        XCTAssertEqual(flow.displayedSceneForTest.nodes, PowerFlowScene.make(snapshot: battery()).nodes)
        assertRenderedNodes(flow)
    }

    func testConnectionHintDoesNotRestartAnIdenticalMeasuredPresentation() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        var measured = battery()
        measured.deviceOutputW = 7.5
        flow.update(snapshot: measured, animated: true)
        let count = flow.transitionInstallationsForTest
        measured.hasConnectedUSBDevice = true
        flow.update(snapshot: measured, animated: true)
        measured.hasConnectedUSBDevice = false
        flow.update(snapshot: measured, animated: true)
        XCTAssertEqual(flow.transitionInstallationsForTest, count)
    }

    func testStaticAndDetachedStateChangesDoNotInstallTransitions() {
        _ = NSApplication.shared
        let flow = PowerFlowView()
        flow.layoutSubtreeIfNeeded()
        flow.setAnimationsEnabled(true)
        flow.update(snapshot: battery(), animated: true)
        flow.update(snapshot: charging(), animated: true)
        XCTAssertEqual(flow.transitionInstallationsForTest, 0)
        XCTAssertEqual(flow.transitionOverlayCountForTest, 0)
        XCTAssertFalse(flow.transitionIsAnimatingForTest)
        flow.setAnimationsEnabled(false)
    }

    func testDirectSemanticUpdateDiscardsAnOldNumericGeometryAnimation() {
        let (flow, window) = fixture()
        defer { flow.setAnimationsEnabled(false); window.contentView = nil }
        let layers = flow.pipeGeometryLayersForTest.filter {
            !($0 is CAGradientLayer) || $0.animation(forKey: "flow") != nil
        }
        let prior = CABasicAnimation(keyPath: "opacity")
        prior.fromValue = 0.4
        prior.toValue = 1
        prior.duration = 2
        layers.forEach { $0.add(prior, forKey: "prior-numeric-geometry") }
        var numeric = battery()
        numeric.batteryW = -40
        numeric.systemW = 40
        flow.update(snapshot: numeric, animated: true)
        XCTAssertTrue(layers.allSatisfy { $0.animation(forKey: "prior-numeric-geometry") != nil })
        flow.update(snapshot: charging(), animated: false)
        XCTAssertTrue(layers.allSatisfy { $0.animation(forKey: "prior-numeric-geometry") == nil })
        XCTAssertFalse(flow.transitionIsAnimatingForTest)
    }
}
