import CoreGraphics
import XCTest
@testable import Wattson

final class PowerFlowMorphTests: XCTestCase {
    private var fixtures: [PowerFlowScene] {
        [PowerSnapshot(plugged: true, adapterW: 68, batteryW: 22.2, systemW: 45.8),
         PowerSnapshot(plugged: true, adapterW: 68, batteryW: 22.2, systemW: 45.8, deviceOutputW: 7.5),
         PowerSnapshot(plugged: true, adapterW: 30, batteryW: -9.7, systemW: 39.7),
         PowerSnapshot(plugged: true, adapterW: 30, batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2),
         PowerSnapshot(batteryW: -39.7, systemW: 39.7, deviceOutputW: 12.2),
         PowerSnapshot(plugged: true, adapterW: 52, systemW: 52, hasConnectedUSBDevice: true),
         PowerSnapshot(batteryW: -39.7, systemW: 39.7, hasConnectedUSBDevice: true),
         PowerSnapshot()].map(PowerFlowScene.make)
    }

    private func assertSame(_ actual: PowerFlowScene, _ expected: PowerFlowScene,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.layout, expected.layout, file: file, line: line)
        XCTAssertEqual(actual.nodes, expected.nodes, file: file, line: line)
        XCTAssertEqual(actual.nodeVisible, expected.nodeVisible, file: file, line: line)
        XCTAssertEqual(actual.nodeCompact, expected.nodeCompact, file: file, line: line)
        XCTAssertEqual(actual.edges, expected.edges, file: file, line: line)
        XCTAssertEqual(actual.jointStart, expected.jointStart, file: file, line: line)
        XCTAssertEqual(actual.jointEnd, expected.jointEnd, file: file, line: line)
        XCTAssertEqual(actual.idleBattery, expected.idleBattery, file: file, line: line)
        XCTAssertEqual(actual.idleDevice, expected.idleDevice, file: file, line: line)
        XCTAssertEqual(actual.mixedCommonWidth, expected.mixedCommonWidth, file: file, line: line)
    }

    private func assertConnected(_ scene: PowerFlowScene,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let common = scene.edges[FlowEdgeRole.common.rawValue]
        var boundary = common.geometry.start.y - common.startWidth / 2
        for role: FlowEdgeRole in [.adapterInput, .batteryInput] {
            let branch = scene.edges[role.rawValue]
            XCTAssertEqual(branch.geometry.end.x, common.geometry.start.x, file: file, line: line)
            XCTAssertEqual(branch.geometry.end.y - branch.endWidth / 2, boundary,
                           accuracy: 0.000_001, file: file, line: line)
            boundary += branch.endWidth
        }
        XCTAssertEqual(boundary, common.geometry.start.y + common.startWidth / 2,
                       accuracy: 0.000_001, file: file, line: line)
        boundary = common.geometry.end.y - common.endWidth / 2
        for role: FlowEdgeRole in [.systemOutput, .batteryCharge, .deviceOutput] {
            let branch = scene.edges[role.rawValue]
            XCTAssertEqual(branch.geometry.start.x, common.geometry.end.x, file: file, line: line)
            XCTAssertEqual(branch.geometry.start.y - branch.startWidth / 2, boundary,
                           accuracy: 0.000_001, file: file, line: line)
            boundary += branch.startWidth
        }
        XCTAssertEqual(boundary, common.geometry.end.y + common.endWidth / 2,
                       accuracy: 0.000_001, file: file, line: line)
    }

    func testAllPairsPreserveExactEndpointsAndFiniteConnectedIntermediateGeometry() {
        for from in fixtures {
            for to in fixtures {
                assertSame(PowerFlowMorph.scene(from: from, to: to, progress: 0), from)
                assertSame(PowerFlowMorph.scene(from: from, to: to, progress: 1), to)
                for step in 1..<40 {
                    let scene = PowerFlowMorph.scene(from: from, to: to, progress: CGFloat(step) / 40)
                    assertConnected(scene)
                    XCTAssertTrue(scene.nodeVisible[1])
                    XCTAssertLessThanOrEqual(scene.nodes[1].y, 168)
                    for edge in scene.edges {
                        XCTAssertTrue(edge.startWidth.isFinite && edge.endWidth.isFinite)
                        XCTAssertGreaterThanOrEqual(edge.startWidth, 0)
                        XCTAssertGreaterThanOrEqual(edge.endWidth, 0)
                        for point in [edge.geometry.start, edge.geometry.control1,
                                      edge.geometry.control2, edge.geometry.end] {
                            XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                        }
                        if edge.startWidth > 0 && edge.endWidth > 0 {
                            XCTAssertLessThanOrEqual(edge.geometry.start.x, edge.geometry.control1.x + 0.000_001)
                            XCTAssertLessThanOrEqual(edge.geometry.control1.x, edge.geometry.control2.x + 0.000_001)
                            XCTAssertLessThanOrEqual(edge.geometry.control2.x, edge.geometry.end.x + 0.000_001)
                        }
                    }
                }
            }
        }
    }

    func testBatteryChangesDirectionOnlyAfterTravellingThroughLowerLane() {
        for from in fixtures {
            for to in fixtures where from.nodes[1].x != to.nodes[1].x {
                for progress: CGFloat in [0.2, 0.3, 0.4, 0.5, 0.6] {
                    let scene = PowerFlowMorph.scene(from: from, to: to, progress: progress)
                    for role: FlowEdgeRole in [.batteryInput, .batteryCharge] {
                        XCTAssertEqual(scene.edges[role.rawValue].startWidth, 0)
                        XCTAssertEqual(scene.edges[role.rawValue].endWidth, 0)
                    }
                    let battery = scene.nodes[1]
                    XCTAssertEqual(scene.edges[FlowEdgeRole.batteryInput.rawValue].geometry.start,
                                   CGPoint(x: battery.x + 13, y: battery.y))
                    XCTAssertEqual(scene.edges[FlowEdgeRole.batteryCharge.rawValue].geometry.end,
                                   CGPoint(x: battery.x - 13, y: battery.y))
                }
                let middle = PowerFlowMorph.scene(from: from, to: to, progress: 0.4)
                XCTAssertEqual(middle.nodes[1].x, 164, accuracy: 0.000_001)
                XCTAssertEqual(middle.nodes[1].y, 151, accuracy: 0.000_001)
                XCTAssertTrue(middle.nodeVisible[1])
                XCTAssertEqual(PowerFlowMorph.scene(from: from, to: to, progress: 0.2).nodes[1], from.nodes[1])
                XCTAssertEqual(PowerFlowMorph.scene(from: from, to: to, progress: 0.6).nodes[1], to.nodes[1])
            }
        }
    }

    func testUSBMovesAfterBatteryVacatesAndBeforeBatteryReturns() {
        let adapter = fixtures[1]
        let mixed = fixtures[3]
        let leaving = PowerFlowMorph.scene(from: adapter, to: mixed, progress: 0.5)
        XCTAssertEqual(leaving.nodes[3], adapter.nodes[3])
        XCTAssertGreaterThan(leaving.nodes[3].x - leaving.nodes[1].x, 92)
        let returning = PowerFlowMorph.scene(from: mixed, to: adapter, progress: 0.3)
        XCTAssertEqual(returning.nodes[3], adapter.nodes[3])
        XCTAssertGreaterThan(returning.nodes[3].x - returning.nodes[1].x, 92)
    }

    func testRetargetingStartsAtPresentedSceneWithoutGeometryOrWidthJump() {
        for from in fixtures {
            for firstTarget in fixtures {
                let presented = PowerFlowMorph.scene(from: from, to: firstTarget, progress: 0.43)
                for target in fixtures {
                    assertSame(PowerFlowMorph.scene(from: presented, to: target, progress: 0), presented)
                    let next = PowerFlowMorph.scene(from: presented, to: target, progress: 0.000_001)
                    for index in presented.nodes.indices where presented.nodeVisible[index] {
                        XCTAssertEqual(next.nodes[index].x, presented.nodes[index].x, accuracy: 0.001)
                        XCTAssertEqual(next.nodes[index].y, presented.nodes[index].y, accuracy: 0.001)
                    }
                    for index in presented.edges.indices {
                        XCTAssertEqual(next.edges[index].startWidth, presented.edges[index].startWidth, accuracy: 0.001)
                        XCTAssertEqual(next.edges[index].endWidth, presented.edges[index].endWidth, accuracy: 0.001)
                        guard presented.edges[index].startWidth > 0 || presented.edges[index].endWidth > 0 else { continue }
                        let old = presented.edges[index].geometry, new = next.edges[index].geometry
                        for (a, b) in zip([old.start, old.control1, old.control2, old.end],
                                          [new.start, new.control1, new.control2, new.end]) {
                            XCTAssertEqual(a.x, b.x, accuracy: 0.001)
                            XCTAssertEqual(a.y, b.y, accuracy: 0.001)
                        }
                    }
                    assertConnected(next)
                }
            }
        }
    }

    func testIdleBatteryConnectionIsAbsentWhileBatteryCrossesColumns() {
        let idle = fixtures[5], battery = fixtures[6]
        for progress: CGFloat in [0.2, 0.4, 0.6] {
            XCTAssertNil(PowerFlowMorph.scene(from: idle, to: battery, progress: progress).idleBattery)
            XCTAssertNil(PowerFlowMorph.scene(from: battery, to: idle, progress: progress).idleBattery)
        }
        XCTAssertNotNil(PowerFlowMorph.scene(from: idle, to: battery, progress: 0.1).idleBattery)
        XCTAssertNotNil(PowerFlowMorph.scene(from: battery, to: idle, progress: 0.9).idleBattery)
    }

    func testArrivingBatteryBranchesReachFullOuterWidthBeforeTheFinalTick() {
        for from in fixtures {
            for to in fixtures where from.nodes[1].x != to.nodes[1].x {
                let arriving: FlowEdgeRole = to.nodes[1].x < from.nodes[1].x ? .batteryInput : .batteryCharge
                let departing: FlowEdgeRole = arriving == .batteryInput ? .batteryCharge : .batteryInput
                let target = to.edges[arriving.rawValue]
                for progress: CGFloat in [0.65, 0.75, 0.85, 0.9, 0.95, 0.999] {
                    let scene = PowerFlowMorph.scene(from: from, to: to, progress: progress)
                    let branch = scene.edges[arriving.rawValue]
                    let retired = scene.edges[departing.rawValue]
                    XCTAssertEqual(scene.nodes[1], to.nodes[1], "Admission starts only after the battery arrives")
                    XCTAssertEqual(retired.startWidth, 0)
                    XCTAssertEqual(retired.endWidth, 0)
                    assertConnected(scene)
                    let outer = arriving == .batteryInput ? branch.startWidth : branch.endWidth
                    let targetOuter = arriving == .batteryInput ? target.startWidth : target.endWidth
                    if progress < 0.85, targetOuter > 0 {
                        XCTAssertGreaterThan(outer, 0, "The branch must grow well before the deadline")
                        XCTAssertLessThan(outer, targetOuter)
                    } else {
                        XCTAssertEqual(outer, targetOuter, accuracy: 0.000_001)
                        XCTAssertGreaterThanOrEqual(branch.startWidth, target.startWidth * 0.8)
                        XCTAssertGreaterThanOrEqual(branch.endWidth, target.endWidth * 0.8)
                    }
                }
            }
        }
    }

    func testNewAdapterNeverCreatesAnUprightFoldedSourceLeg() {
        let from = fixtures[4], to = fixtures[1]
        XCTAssertFalse(from.nodeVisible[0])
        for step in 1..<40 {
            let scene = PowerFlowMorph.scene(from: from, to: to, progress: CGFloat(step) / 40)
            XCTAssertEqual(scene.nodes[0].y, scene.jointStart.y, accuracy: 0.000_001)
            let input = scene.edges[FlowEdgeRole.adapterInput.rawValue]
            XCTAssertEqual(input.geometry.start.x, input.geometry.end.x)
            XCTAssertLessThanOrEqual(abs(input.geometry.end.y - input.geometry.start.y),
                                    scene.edges[FlowEdgeRole.common.rawValue].startWidth / 2 + 0.000_001)
            assertConnected(scene)
        }
    }

    func testNewUSBWaitsAtItsFinalSlotAfterNeighboursHaveCleared() {
        for (from, to) in [(fixtures[0], fixtures[1]), (fixtures[2], fixtures[3]),
                           (fixtures[7], fixtures[6])] {
            XCTAssertFalse(from.nodeVisible[3])
            for progress: CGFloat in [0.01, 0.3, 0.6, 0.8] {
                let scene = PowerFlowMorph.scene(from: from, to: to, progress: progress)
                XCTAssertEqual(scene.nodes[3], to.nodes[3])
                if progress >= 0.6 {
                    XCTAssertEqual(scene.nodes[2], to.nodes[2])
                    XCTAssertEqual(scene.nodes[1], to.nodes[1])
                }
                assertConnected(scene)
            }
        }
    }

    func testNewAdapterHasClearLeftColumnBeforeReveal() {
        let from = fixtures[4], to = fixtures[3]
        let scene = PowerFlowMorph.scene(from: from, to: to, progress: 0.6)
        XCTAssertEqual(scene.nodes[1], to.nodes[1])
        XCTAssertGreaterThanOrEqual(scene.nodes[1].y - scene.nodes[0].y, 74)
    }

    func testNormalMotionUsesSmoothstepAndInvalidProgressReturnsSource() {
        let from = fixtures[3], to = fixtures[4]
        let scene = PowerFlowMorph.scene(from: from, to: to, progress: 0.25)
        XCTAssertEqual(scene.nodes[1].y, 129 + (90 - 129) * 0.15625, accuracy: 0.000_001)
        for progress: CGFloat in [-1, .nan, -.infinity] {
            assertSame(PowerFlowMorph.scene(from: from, to: to, progress: progress), from)
        }
        assertSame(PowerFlowMorph.scene(from: from, to: to, progress: 2), to)
    }
}
