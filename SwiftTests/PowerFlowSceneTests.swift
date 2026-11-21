import CoreGraphics
import XCTest
@testable import Wattson

final class PowerFlowSceneTests: XCTestCase {
    private let charging = PowerSnapshot(percent: 72, plugged: true, adapterW: 68,
                                         batteryW: 22.2, systemW: 45.8)
    private let mixed = PowerSnapshot(percent: 41, plugged: true, adapterW: 30,
                                      batteryW: -9.7, systemW: 39.7)
    private let battery = PowerSnapshot(percent: 67, batteryW: -39.7, systemW: 39.7)

    private func withUSB(_ snapshot: PowerSnapshot, watts: Double? = 12.2) -> PowerSnapshot {
        var result = snapshot
        result.deviceOutputW = watts
        result.hasConnectedUSBDevice = true
        return result
    }

    private func edge(_ scene: PowerFlowScene, _ role: FlowEdgeRole) -> FlowEdgePose {
        scene.edges[role.rawValue]
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.000_001, file: file, line: line)
    }

    private func assertFullCurve(_ geometry: PipeGeometry, startY: CGFloat, endY: CGFloat,
                                 file: StaticString = #filePath, line: UInt = #line) {
        assertPoint(geometry.start, CGPoint(x: 53, y: startY), file: file, line: line)
        assertPoint(geometry.control1, CGPoint(x: 138, y: startY), file: file, line: line)
        assertPoint(geometry.control2, CGPoint(x: 190, y: endY), file: file, line: line)
        assertPoint(geometry.end, CGPoint(x: 275, y: endY), file: file, line: line)
    }

    func testFiveRestingLayoutsKeepSemanticNodeIdentitiesAndOriginalPositions() {
        let fixtures: [(PowerSnapshot, FlowLayout, [CGPoint], [Bool], [Bool])] = [
            (charging, .adapterLed,
             [.init(x: 40, y: 90), .init(x: 288, y: 129), .init(x: 288, y: 51), .init(x: 288, y: 129)],
             [true, true, true, false], [false, false, false, false]),
            (mixed, .batteryLed,
             [.init(x: 40, y: 51), .init(x: 40, y: 129), .init(x: 288, y: 90), .init(x: 288, y: 129)],
             [true, true, true, false], [false, false, false, false]),
            (withUSB(battery), .batteryOutputSplit,
             [.init(x: 40, y: 51), .init(x: 40, y: 90), .init(x: 288, y: 51), .init(x: 288, y: 129)],
             [false, true, true, true], [false, false, false, false]),
            (withUSB(charging), .adapterOutputSplit,
             [.init(x: 40, y: 96), .init(x: 288, y: 96), .init(x: 288, y: 26), .init(x: 288, y: 166)],
             [true, true, true, true], [false, true, true, true]),
            (withUSB(mixed), .mixedOutputSplit,
             [.init(x: 40, y: 51), .init(x: 40, y: 129), .init(x: 288, y: 51), .init(x: 288, y: 129)],
             [true, true, true, true], [false, false, false, false])
        ]
        for (snapshot, layout, nodes, visible, compact) in fixtures {
            let scene = PowerFlowScene.make(snapshot: snapshot)
            XCTAssertEqual(scene.layout, layout)
            XCTAssertEqual(scene.nodes, nodes)
            XCTAssertEqual(scene.nodeVisible, visible)
            XCTAssertEqual(scene.nodeCompact, compact)
            XCTAssertEqual(scene.edges.count, 6)
        }
    }

    func testAdapterLedKeepsOriginalFullCurvesAndFoldsInputIntoSource() {
        let scene = PowerFlowScene.make(snapshot: charging)
        let systemWidth = VisualEncoding.thickness(45.8)
        let chargeWidth = VisualEncoding.thickness(22.2)
        let system = edge(scene, .systemOutput)
        let charge = edge(scene, .batteryCharge)
        assertFullCurve(system.geometry, startY: 90 - chargeWidth / 2, endY: 51)
        assertFullCurve(charge.geometry, startY: 90 + systemWidth / 2, endY: 129)
        XCTAssertEqual(system.startWidth, systemWidth, accuracy: 0.000_001)
        XCTAssertEqual(charge.startWidth, chargeWidth, accuracy: 0.000_001)
        for role: FlowEdgeRole in [.adapterInput, .common] {
            let folded = edge(scene, role)
            XCTAssertTrue(folded.isCollapsed)
            XCTAssertGreaterThan(folded.startWidth, 0)
            assertPoint(folded.geometry.start, CGPoint(x: 53, y: 90))
        }
        XCTAssertNil(scene.idleBattery)
    }

    func testThreeWayAdapterKeepsOriginalThirtyPointPackedBranches() {
        let scene = PowerFlowScene.make(snapshot: withUSB(charging, watts: 7.5))
        let raw = [38.3, 22.2, 7.5].map(VisualEncoding.thickness)
        let scale = min(1, 30 / raw.reduce(0, +))
        let widths = raw.map { $0 * scale }
        let starts = [96 - (widths[1] + widths[2]) / 2,
                      96 + (widths[0] - widths[2]) / 2,
                      96 + (widths[0] + widths[1]) / 2]
        for (index, role) in [FlowEdgeRole.systemOutput, .batteryCharge, .deviceOutput].enumerated() {
            let branch = edge(scene, role)
            assertFullCurve(branch.geometry, startY: starts[index], endY: [26, 96, 166][index])
            XCTAssertEqual(branch.startWidth, widths[index], accuracy: 0.000_001)
            XCTAssertEqual(branch.startWidth, branch.endWidth)
            XCTAssertEqual(branch.verticalTaper, 0)
        }
    }

    func testBatteryLedKeepsBothOriginalInputCurvesAndFoldsSystemLeg() {
        let scene = PowerFlowScene.make(snapshot: mixed)
        let adapterWidth = VisualEncoding.thickness(30)
        let batteryWidth = VisualEncoding.thickness(9.7)
        assertFullCurve(edge(scene, .adapterInput).geometry,
                        startY: 51, endY: 90 - batteryWidth / 2)
        assertFullCurve(edge(scene, .batteryInput).geometry,
                        startY: 129, endY: 90 + adapterWidth / 2)
        for role: FlowEdgeRole in [.systemOutput, .common] {
            let folded = edge(scene, role)
            XCTAssertTrue(folded.isCollapsed)
            XCTAssertGreaterThan(folded.startWidth, 0)
            assertPoint(folded.geometry.start, CGPoint(x: 275, y: 90))
        }
        XCTAssertEqual(edge(scene, .batteryCharge).startWidth, 0)
    }

    func testBatteryUSBKeepsBatteryAsSourceAndPreservesFullOutputCurves() {
        let scene = PowerFlowScene.make(snapshot: withUSB(battery))
        let systemWidth = VisualEncoding.thickness(27.5)
        let deviceWidth = VisualEncoding.thickness(12.2)
        assertFullCurve(edge(scene, .systemOutput).geometry,
                        startY: 90 - deviceWidth / 2, endY: 51)
        assertFullCurve(edge(scene, .deviceOutput).geometry,
                        startY: 90 + systemWidth / 2, endY: 129)
        XCTAssertTrue(edge(scene, .batteryInput).isCollapsed)
        XCTAssertGreaterThan(edge(scene, .batteryInput).startWidth, 0)
        XCTAssertEqual(edge(scene, .adapterInput).startWidth, 0)
        XCTAssertEqual(scene.nodes[1], CGPoint(x: 40, y: 90))
        XCTAssertEqual(scene.nodes[3], CGPoint(x: 288, y: 129))
        XCTAssertEqual(edge(scene, .batteryCharge).geometry.end.x, 27,
                       "Even a zero-width edge remains attached to the semantic battery node")
    }

    func testMixedNeckKeepsApprovedNarrowingAndExactCubicControls() {
        let scene = PowerFlowScene.make(snapshot: withUSB(mixed))
        let incoming = [30.0, 9.7].map(VisualEncoding.thickness).reduce(0, +)
        let outgoing = [27.5, 12.2].map(VisualEncoding.thickness).reduce(0, +)
        let expectedNeck = min(36, min(incoming, outgoing)) * 0.68
        XCTAssertEqual(scene.mixedCommonWidth, expectedNeck, accuracy: 0.000_001)
        XCTAssertLessThan(expectedNeck, incoming)
        for role: FlowEdgeRole in [.adapterInput, .batteryInput] {
            let branch = edge(scene, role)
            XCTAssertEqual(branch.geometry.start.x, 53)
            XCTAssertEqual(branch.geometry.control1.x, 88.5, accuracy: 0.000_001)
            XCTAssertEqual(branch.geometry.control2.x, 110.5, accuracy: 0.000_001)
            XCTAssertEqual(branch.geometry.end.x, 146)
            XCTAssertLessThan(branch.endWidth, branch.startWidth)
            XCTAssertEqual(branch.verticalTaper, 1)
        }
        for role: FlowEdgeRole in [.systemOutput, .deviceOutput] {
            let branch = edge(scene, role)
            XCTAssertEqual(branch.geometry.start.x, 182)
            XCTAssertEqual(branch.geometry.control1.x, 217.5, accuracy: 0.000_001)
            XCTAssertEqual(branch.geometry.control2.x, 239.5, accuracy: 0.000_001)
            XCTAssertEqual(branch.geometry.end.x, 275)
            XCTAssertLessThan(branch.startWidth, branch.endWidth)
        }
        XCTAssertEqual(edge(scene, .common).geometry, PipeGeometry(
            start: .init(x: 146, y: 90), control1: .init(x: 158, y: 90),
            control2: .init(x: 170, y: 90), end: .init(x: 182, y: 90)))
    }

    func testEveryJointPacksContiguousBandsWithoutGapsOrOverlaps() {
        let fixtures = [charging, mixed, battery, withUSB(charging), withUSB(mixed),
                        withUSB(battery), withUSB(mixed, watts: nil),
                        PowerSnapshot(plugged: true, adapterW: 52, systemW: 52),
                        PowerSnapshot()]
        for snapshot in fixtures {
            let scene = PowerFlowScene.make(snapshot: snapshot)
            let common = edge(scene, .common)
            var inputBoundary = common.geometry.start.y - common.startWidth / 2
            for role: FlowEdgeRole in [.adapterInput, .batteryInput] {
                let branch = edge(scene, role)
                XCTAssertEqual(branch.geometry.end.x, common.geometry.start.x)
                XCTAssertEqual(branch.geometry.end.y - branch.endWidth / 2,
                               inputBoundary, accuracy: 0.000_001)
                inputBoundary += branch.endWidth
            }
            XCTAssertEqual(inputBoundary, common.geometry.start.y + common.startWidth / 2,
                           accuracy: 0.000_001)
            var outputBoundary = common.geometry.end.y - common.endWidth / 2
            for role: FlowEdgeRole in [.systemOutput, .batteryCharge, .deviceOutput] {
                let branch = edge(scene, role)
                XCTAssertEqual(branch.geometry.start.x, common.geometry.end.x)
                XCTAssertEqual(branch.geometry.start.y - branch.startWidth / 2,
                               outputBoundary, accuracy: 0.000_001)
                outputBoundary += branch.startWidth
            }
            XCTAssertEqual(outputBoundary, common.geometry.end.y + common.endWidth / 2,
                           accuracy: 0.000_001)
        }
    }

    func testPendingUSBHasOnlyAnIdleConnectionAndNeverAnInventedEnergyPipe() throws {
        for initial in [charging, mixed, battery] {
            for watts: Double? in [nil, 0, -1, .nan, .infinity, 1000] {
                let scene = PowerFlowScene.make(snapshot: withUSB(initial, watts: watts))
                XCTAssertTrue(scene.nodeVisible[3])
                XCTAssertEqual(edge(scene, .deviceOutput).startWidth, 0)
                XCTAssertEqual(edge(scene, .deviceOutput).endWidth, 0)
                let idle = try XCTUnwrap(scene.idleDevice)
                XCTAssertGreaterThanOrEqual(idle.start.x, 58.5, "The waiting branch must clear the source icon")
                let outputWidth = [FlowEdgeRole.systemOutput, .batteryCharge, .deviceOutput]
                    .reduce(CGFloat.zero) { $0 + edge(scene, $1).startWidth }
                XCTAssertEqual(idle.start.y, scene.jointEnd.y + outputWidth / 2, accuracy: 0.000_001)
                if outputWidth > 0 { XCTAssertGreaterThan(idle.start.y, scene.jointEnd.y) }
                XCTAssertLessThan(idle.start.x, idle.end.x)
                XCTAssertEqual(idle.end.x, 269.5)
                XCTAssertEqual(idle.end.y, scene.nodes[3].y)
            }
            var partial = withUSB(initial)
            partial.deviceOutputIsComplete = false
            let scene = PowerFlowScene.make(snapshot: partial)
            XCTAssertEqual(edge(scene, .deviceOutput).startWidth, 0)
            XCTAssertNotNil(scene.idleDevice)
        }
        let idleBattery = PowerFlowScene.make(snapshot: PowerSnapshot(
            plugged: true, adapterW: 52, systemW: 52))
        XCTAssertEqual(try XCTUnwrap(idleBattery.idleBattery).start.x, 58.5)
        XCTAssertEqual(try XCTUnwrap(idleBattery.idleBattery).end.x, 269.5)
    }

    func testDeadbandUSBReadingDoesNotEnergizeBatteryOutput() {
        for batteryW in [-0.3, 0, 0.3] {
            let scene = PowerFlowScene.make(snapshot: PowerSnapshot(
                batteryW: batteryW, systemW: 10, deviceOutputW: 2, hasConnectedUSBDevice: true))
            XCTAssertEqual(scene.layout, .batteryOutputSplit)
            XCTAssertTrue(scene.edges.allSatisfy { $0.startWidth == 0 && $0.endWidth == 0 })
        }
    }

    func testZeroAndUnavailableReadingsLeaveFiniteGeometry() {
        for snapshot in [PowerSnapshot(), PowerSnapshot(plugged: true),
                         PowerSnapshot(hasPowerReading: false),
                         PowerSnapshot(hasConnectedUSBDevice: true),
                         PowerSnapshot(plugged: true, hasConnectedUSBDevice: true)] {
            let scene = PowerFlowScene.make(snapshot: snapshot)
            for branch in scene.edges {
                XCTAssertEqual(branch.startWidth, 0)
                XCTAssertEqual(branch.endWidth, 0)
                for point in [branch.geometry.start, branch.geometry.control1,
                              branch.geometry.control2, branch.geometry.end] {
                    XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                }
            }
        }
    }
}
