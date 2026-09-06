import AppKit
import XCTest
@testable import Wattson

final class PowerFlowEfficiencyTests: XCTestCase {
    private let curve = PipeGeometry(
        start: CGPoint(x: 53, y: 116), control1: CGPoint(x: 138, y: 116),
        control2: CGPoint(x: 190, y: 77), end: CGPoint(x: 275, y: 77)
    )

    private func configure(_ pipe: PipeBundle, geometry: PipeGeometry,
                           count: Int = 5, period: CFTimeInterval = 1.2,
                           hot: Bool = false, animating: Bool = true,
                           topology: String = "battery") {
        pipe.apply(geometry: geometry, thickness: 12, color: .white,
                   bounds: CGRect(x: 0, y: 0, width: 328, height: 176), animated: false)
        pipe.rebuildParticles(count: count, thickness: 12, color: .white,
                              period: period, seed: 29, hot: hot,
                              animating: animating, topology: topology)
    }

    private func makeFlow(snapshot: PowerSnapshot) -> PowerFlowView {
        let flow = PowerFlowView()
        flow.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                            height: PowerFlowView.preferredHeight)
        flow.layoutSubtreeIfNeeded()
        flow.update(snapshot: snapshot, animated: false)
        flow.setAnimationsEnabled(true)
        return flow
    }

    private func rides(_ particles: [CALayer]) throws -> [CAKeyframeAnimation] {
        try particles.map { try XCTUnwrap($0.animation(forKey: "ride") as? CAKeyframeAnimation) }
    }

    func testIdenticalCurveDoesNotReinstallRidesAndStillRetimesSpeed() throws {
        let pipe = PipeBundle()
        configure(pipe, geometry: curve)
        let particles = pipe.particleLayersForTest
        let initialRides = try rides(particles)
        let installations = pipe.particleRideInstallationsForTest
        let geometryUpdates = pipe.particleGeometryUpdatesForTest
        XCTAssertEqual(installations, 5)

        for _ in 0..<100 { configure(pipe, geometry: curve, period: 0.8) }

        XCTAssertEqual(pipe.particleLayersForTest.map(ObjectIdentifier.init),
                       particles.map(ObjectIdentifier.init))
        XCTAssertEqual(pipe.particleRideInstallationsForTest, installations)
        XCTAssertEqual(pipe.particleGeometryUpdatesForTest, geometryUpdates)
        for (particle, initialRide) in zip(particles, initialRides) {
            let current = try XCTUnwrap(particle.animation(forKey: "ride") as? CAKeyframeAnimation)
            XCTAssertEqual(particle.speed, 3, accuracy: 0.001)
            XCTAssertEqual(current.beginTime, initialRide.beginTime)
            XCTAssertEqual(current.timeOffset, initialRide.timeOffset)
        }
    }

    func testDriftingBatteryWattsKeepFixedCurveRidesWhileUpdatingSpeed() throws {
        let initial = PowerSnapshot(percent: 80, plugged: false, adapterW: 0,
                                    batteryW: -30, systemW: 30)
        let flow = makeFlow(snapshot: initial)
        let particles = flow.particleLayersForTest
        let installations = flow.particleRideInstallationsForTest
        let geometryUpdates = flow.particleGeometryUpdatesForTest
        let oldSpeed = try XCTUnwrap(particles.first).speed
        for watts in [30.0, 31.0, 32.0] {
            var snapshot = initial
            snapshot.batteryW = -watts
            snapshot.systemW = watts
            flow.update(snapshot: snapshot, animated: false)
        }
        XCTAssertEqual(flow.topologyForTest, "batteryLed")
        XCTAssertEqual(flow.particleLayersForTest.map(ObjectIdentifier.init),
                       particles.map(ObjectIdentifier.init))
        XCTAssertEqual(flow.particleRideInstallationsForTest, installations)
        XCTAssertEqual(flow.particleGeometryUpdatesForTest, geometryUpdates)
        XCTAssertGreaterThan(try XCTUnwrap(particles.first).speed, oldSpeed)
        XCTAssertEqual(flow.branchThicknessesForTest[1], VisualEncoding.thickness(32))
    }

    func testActualUSBandChargingSplitDriftRetargetsWithoutResettingPhase() throws {
        let pairs: [(PowerSnapshot, PowerSnapshot)] = [
            (PowerSnapshot(percent: 80, plugged: false, adapterW: 0,
                           batteryW: -40, systemW: 40, deviceOutputW: 7),
             PowerSnapshot(percent: 80, plugged: false, adapterW: 0,
                           batteryW: -40, systemW: 40, deviceOutputW: 7.2)),
            (PowerSnapshot(percent: 80, plugged: true, adapterW: 60,
                           batteryW: 20, systemW: 40),
             PowerSnapshot(percent: 80, plugged: true, adapterW: 60,
                           batteryW: 19.8, systemW: 40.2)),
        ]
        for (initial, changed) in pairs {
            let flow = makeFlow(snapshot: initial)
            let particles = flow.particleLayersForTest
            let originalRides = try rides(particles)
            let originalPositions = particles.map(\.position)
            let installations = flow.particleRideInstallationsForTest
            let geometryUpdates = flow.particleGeometryUpdatesForTest
            flow.update(snapshot: changed, animated: false)
            XCTAssertEqual(flow.particleLayersForTest.map(ObjectIdentifier.init),
                           particles.map(ObjectIdentifier.init))
            XCTAssertEqual(flow.particleRideInstallationsForTest, installations + particles.count)
            XCTAssertEqual(flow.particleGeometryUpdatesForTest, geometryUpdates + 2)
            XCTAssertNotEqual(particles.map(\.position), originalPositions)
            for (old, current) in zip(originalRides, try rides(particles)) {
                XCTAssertNotEqual(try XCTUnwrap(old.path).boundingBox,
                                  try XCTUnwrap(current.path).boundingBox)
                XCTAssertEqual(current.beginTime, old.beginTime)
                XCTAssertEqual(current.timeOffset, old.timeOffset)
                XCTAssertEqual(current.duration, old.duration)
                XCTAssertEqual(current.speed, old.speed)
            }
            flow.update(snapshot: changed, animated: false)
            XCTAssertEqual(flow.particleRideInstallationsForTest, installations + particles.count)
            XCTAssertEqual(flow.particleGeometryUpdatesForTest, geometryUpdates + 2)
        }
    }

    func testPoolAndTopologyChangesStillInstallRidesForEveryNewParticle() {
        let pipe = PipeBundle()
        configure(pipe, geometry: curve)
        var previous = pipe.particleLayersForTest
        for (count, hot, topology) in [(7, false, "battery"), (7, true, "battery"),
                                      (7, false, "battery"), (7, false, "adapter")] {
            let installations = pipe.particleRideInstallationsForTest
            configure(pipe, geometry: curve, count: count, hot: hot, topology: topology)
            let current = pipe.particleLayersForTest
            XCTAssertEqual(current.count, count)
            XCTAssertTrue(Set(previous.map(ObjectIdentifier.init))
                .isDisjoint(with: current.map(ObjectIdentifier.init)))
            XCTAssertEqual(pipe.particleRideInstallationsForTest, installations + count)
            configure(pipe, geometry: curve, count: count, hot: hot, topology: topology)
            XCTAssertEqual(pipe.particleRideInstallationsForTest, installations + count)
            previous = current
        }
    }

    func testStaticParticlesFollowNewGeometryAndResumeAfterMotionChanges() throws {
        let pipe = PipeBundle()
        configure(pipe, geometry: curve, animating: false)
        let staticParticles = pipe.particleLayersForTest
        let positions = staticParticles.map(\.position)
        XCTAssertEqual(pipe.particleRideInstallationsForTest, 0)
        var shifted = curve
        shifted.end.y += 0.125
        shifted.control2.y += 0.125
        configure(pipe, geometry: shifted, animating: false)
        XCTAssertEqual(pipe.particleLayersForTest.map(ObjectIdentifier.init),
                       staticParticles.map(ObjectIdentifier.init))
        XCTAssertNotEqual(staticParticles.map(\.position), positions)
        XCTAssertTrue(staticParticles.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        XCTAssertEqual(pipe.particleGeometryUpdatesForTest, 2)
        configure(pipe, geometry: shifted, animating: false)
        XCTAssertEqual(pipe.particleGeometryUpdatesForTest, 2)

        configure(pipe, geometry: shifted)
        XCTAssertEqual(try rides(pipe.particleLayersForTest).count, 5)
        XCTAssertEqual(pipe.particleRideInstallationsForTest, 5)
        pipe.stopFlow()
        XCTAssertTrue(pipe.particleLayersForTest.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        configure(pipe, geometry: shifted)
        XCTAssertEqual(try rides(pipe.particleLayersForTest).count, 5)
        XCTAssertEqual(pipe.particleRideInstallationsForTest, 10)
    }

    func testEmptyPoolAndPopoverReopeningDoNotReuseMissingAnimations() throws {
        let initial = PowerSnapshot(percent: 80, plugged: false, adapterW: 0,
                                    batteryW: -30, systemW: 30)
        let flow = makeFlow(snapshot: initial)
        let count = flow.particleLayersForTest.count
        let installations = flow.particleRideInstallationsForTest
        flow.setAnimationsEnabled(false)
        XCTAssertTrue(flow.particleLayersForTest.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        flow.setAnimationsEnabled(true)
        XCTAssertEqual(try rides(flow.particleLayersForTest).count, count)
        XCTAssertEqual(flow.particleRideInstallationsForTest, installations + count)
        flow.update(snapshot: PowerSnapshot(percent: 80), animated: false)
        XCTAssertTrue(flow.particleLayersForTest.isEmpty)
        flow.update(snapshot: initial, animated: false)
        XCTAssertEqual(try rides(flow.particleLayersForTest).count, count)
        XCTAssertEqual(flow.particleRideInstallationsForTest, installations + count * 2)
        flow.update(snapshot: initial, animated: false)
        XCTAssertEqual(flow.particleRideInstallationsForTest, installations + count * 2)
    }
}
