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
        attachForMotion(flow)
        flow.layoutSubtreeIfNeeded()
        flow.update(snapshot: snapshot, animated: false)
        flow.setAnimationsEnabled(true)
        return flow
    }

    private func attachForMotion(_ flow: PowerFlowView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: flow.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = flow
        addTeardownBlock {
            flow.setAnimationsEnabled(false)
            window.contentView = nil
        }
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
            (PowerSnapshot(percent: 80, plugged: true, adapterW: 60,
                           batteryW: 20, systemW: 40, deviceOutputW: 7),
             PowerSnapshot(percent: 80, plugged: true, adapterW: 60,
                           batteryW: 19.8, systemW: 40.2, deviceOutputW: 7.2)),
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
            let changedBranches = flow.branchThicknessesForTest.count
            XCTAssertEqual(flow.particleGeometryUpdatesForTest, geometryUpdates + changedBranches)
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
            XCTAssertEqual(flow.particleGeometryUpdatesForTest, geometryUpdates + changedBranches)
        }
    }

    func testEmptyPoolAndSingleParticleHysteresis() throws {
        let pipe = PipeBundle()
        configure(pipe, geometry: curve, count: 0, animating: false, topology: "")
        XCTAssertTrue(pipe.particleLayersForTest.isEmpty)
        XCTAssertEqual(pipe.particleGeometryUpdatesForTest, 0)

        for (requested, expected, installations) in [(1, 1, 1), (2, 1, 1),
                                                     (3, 3, 4), (2, 3, 4),
                                                     (0, 0, 4), (1, 1, 5)] {
            configure(pipe, geometry: curve, count: requested)
            XCTAssertEqual(pipe.particleLayersForTest.count, expected)
            XCTAssertEqual(try rides(pipe.particleLayersForTest).count, expected)
            XCTAssertEqual(pipe.particleRideInstallationsForTest, installations)
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

    private func waitUntil(_ predicate: () -> Bool, timeout: TimeInterval = 30,
                           file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(predicate(), "Particle preparation did not settle", file: file, line: line)
    }

    private func layers(in view: NSView) -> [CALayer] {
        var visited = Set<ObjectIdentifier>()
        var result: [CALayer] = []
        func visitLayer(_ layer: CALayer?) {
            guard let layer, visited.insert(ObjectIdentifier(layer)).inserted else { return }
            result.append(layer)
            visitLayer(layer.mask)
            (layer.sublayers ?? []).forEach(visitLayer)
        }
        func visitView(_ view: NSView) {
            visitLayer(view.layer)
            view.subviews.forEach(visitView)
        }
        visitView(view)
        return result
    }

    private func animationCount(_ view: NSView) -> Int {
        layers(in: view).reduce(0) { $0 + ($1.animationKeys()?.count ?? 0) }
    }

    func testIdleBatteryDashEndsOutsideBothIconTiles() {
        let snapshots: [PowerSnapshot] = [
            .init(percent: 99, plugged: true, adapterW: 52, systemW: 52, systemChargingState: .full),
            .init(percent: 80, plugged: true, adapterW: 32, systemW: 32, systemChargingState: .notCharging),
            .init(percent: 99, plugged: true, adapterW: 48.7, systemW: 48.7,
                  deviceOutputW: 14.1, systemChargingState: .full),
            .init(percent: 80, plugged: true, adapterW: 32, systemW: 32,
                  deviceOutputW: 7.5, systemChargingState: .notCharging),
            // Artificial all-zero input checks no-flow geometry; it does not
            // represent unavailable telemetry or an ordinary running Mac.
            .init(percent: 60, plugged: true, deviceOutputW: 0),
        ]
        for snapshot in snapshots {
            let flow = PowerFlowView()
            flow.frame = NSRect(x: 0, y: 0, width: 328, height: 224)
            flow.update(snapshot: snapshot, animated: false)
            flow.layoutSubtreeIfNeeded()
            XCTAssertEqual(flow.idleEndpointXsForTest, [58.5, 269.5],
                           "The dashed line must end outside both 38-point icon tiles, including faded nodes")
        }
    }

    func testMixedUSBReusesPreparedMotionWithoutResettingParticleIdentity() {
        let snapshot = PowerSnapshot(percent: 44, plugged: true, adapterW: 30,
                                     batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2)
        let flow = makeFlow(snapshot: snapshot)
        defer { flow.setAnimationsEnabled(false) }
        let particles = flow.fusionParticleLayerForTest
        waitUntil { !particles.pendingPreparationForTest }
        XCTAssertGreaterThan(particles.cachedFrameBytesForTest, 0)
        XCTAssertLessThan(particles.cachedFrameBytesForTest, 64 * 1_024 * 1_024)
        XCTAssertEqual(particles.particleLayersForTest.count, 10)
        XCTAssertTrue(particles.runtimeCyclesForTest.contains { abs($0 - 3.795860548) < 0.002 },
                      "Enhanced particle repeats its natural two-pass cycle and accumulated delay, not the six-second recording")
        let identities = particles.particleLayersForTest.map(ObjectIdentifier.init)
        let preparations = particles.preparationCountForTest
        let installations = particles.animationInstallationsForTest
        for _ in 0..<50 { flow.update(snapshot: snapshot, animated: false) }
        XCTAssertEqual(particles.preparationCountForTest, preparations)
        XCTAssertEqual(particles.animationInstallationsForTest, installations)
        XCTAssertEqual(particles.particleLayersForTest.map(ObjectIdentifier.init), identities)
        XCTAssertFalse(particles.pendingPreparationForTest)
        XCTAssertNotNil(flow.flowMetricsForTest(), "The mixed blue field retains its shared light motion")

        flow.setAnimationsEnabled(false)
        XCTAssertEqual(animationCount(flow), 0)
        XCTAssertFalse(particles.pendingPreparationForTest)
        flow.setAnimationsEnabled(true)
        waitUntil { !particles.pendingPreparationForTest }
        XCTAssertGreaterThan(animationCount(flow), 0)
        flow.setAnimationsEnabled(false)
        XCTAssertEqual(animationCount(flow), 0)
    }

    func testMixedBluePeakStartsAtCentreAndAllBranchesShareLightMotion() {
        let snapshot = PowerSnapshot(percent: 44, plugged: true, adapterW: 30,
                                     batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let flow = PowerFlowView()
            flow.appearance = NSAppearance(named: appearance)
            flow.frame = NSRect(x: 0, y: 0, width: 328, height: 224)
            attachForMotion(flow)
            flow.layoutSubtreeIfNeeded()
            flow.update(snapshot: snapshot, animated: false)
            XCTAssertEqual(flow.mixedGradientPeakXForTest, 164)
            let fields = layers(in: flow).compactMap { $0 as? CAGradientLayer }.filter { field in
                var ancestor: CALayer? = field
                while let layer = ancestor {
                    if layer.isHidden || layer.opacity <= 0 { return false }
                    ancestor = layer.superlayer
                }
                return true
            }
            XCTAssertEqual(fields.count, 5, "Only the five powered mixed branches contribute a visible field")
            for field in fields {
                let colors = (field.colors as? [CGColor]) ?? []
                let alphas = colors.map(\.alpha)
                guard let maximum = alphas.max(), let locations = field.locations else {
                    XCTFail("No mixed field colour peak"); continue
                }
                let visiblePeaks = alphas.indices.filter { abs(alphas[$0] - maximum) < 0.001 }
                    .map { field.frame.minX + field.frame.width * CGFloat(locations[$0].doubleValue) }
                    .filter { $0 >= 0 && $0 <= 328 }
                XCTAssertEqual(visiblePeaks.count, 1)
                XCTAssertEqual(visiblePeaks.first ?? -1, 164, accuracy: 0.001)
                XCTAssertNil(field.animation(forKey: "flow"))
            }
            flow.setAnimationsEnabled(true)
            let motions = fields.compactMap { $0.animation(forKey: "flow") as? CABasicAnimation }
            XCTAssertEqual(motions.count, 5)
            if let first = motions.first, let referenceField = fields.first {
                for (field, motion) in zip(fields, motions) {
                    XCTAssertEqual(motion.duration, first.duration)
                    XCTAssertEqual(motion.beginTime, first.beginTime)
                    XCTAssertEqual(motion.timeOffset, first.timeOffset)
                    XCTAssertEqual(field.speed, referenceField.speed)
                    XCTAssertEqual(field.beginTime, referenceField.beginTime)
                    XCTAssertEqual(field.timeOffset, referenceField.timeOffset)
                    XCTAssertEqual((motion.byValue as? NSNumber)?.doubleValue, 328)
                }
            }
            flow.setAnimationsEnabled(false)
        }
    }

    func testSlowMixedPreparationAndPendingHandoffSurviveSmallTelemetryChanges() {
        let flow = PowerFlowView()
        flow.appearance = NSAppearance(named: .aqua)
        flow.frame = NSRect(x: 0, y: 0, width: 328, height: 224)
        // A hidden window provides a CA host across the asynchronous wait;
        // unattached view layers can drop autoremove animations on commit.
        let window = NSWindow(contentRect: flow.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = flow
        defer { window.close() }
        flow.layoutSubtreeIfNeeded()
        let runtime = flow.fusionParticleLayerForTest
        let started = expectation(description: "Preparation reached its controlled gate")
        let release = DispatchSemaphore(value: 0)
        runtime.preparationGateForTest = {
            started.fulfill()
            _ = release.wait(timeout: .now() + 30)
        }
        defer { release.signal(); flow.setAnimationsEnabled(false) }
        let readings: [(Double, Double, Double)] = [
            (30.10, 9.65, 12.25), (30.25, 9.60, 12.28), (29.95, 9.80, 12.18),
            (30.15, 9.70, 12.30), (30.05, 9.75, 12.21), (30.20, 9.60, 12.26),
        ]
        func snapshot(_ reading: (Double, Double, Double)) -> PowerSnapshot {
            .init(percent: 44, plugged: true, adapterW: reading.0, batteryW: -reading.1,
                  systemW: reading.0 + reading.1, deviceOutputW: reading.2)
        }
        flow.update(snapshot: snapshot(readings[0]), animated: false)
        flow.setAnimationsEnabled(true)
        wait(for: [started], timeout: 5)
        runtime.preparationGateForTest = nil
        let identities = runtime.particleLayersForTest.map(ObjectIdentifier.init)
        let originalWidths = flow.branchThicknessesForTest
        for reading in readings.dropFirst() { flow.update(snapshot: snapshot(reading), animated: false) }
        XCTAssertEqual(runtime.preparationCountForTest, 1,
                       "New readings must not cancel a compatible job that has not finished yet")
        XCTAssertTrue(runtime.pendingPreparationForTest)
        XCTAssertNotEqual(flow.branchThicknessesForTest, originalWidths)
        XCTAssertEqual(flow.nodePresentationsForTest.first?.value, "30.2 W")
        release.signal()
        waitUntil { !runtime.pendingPreparationForTest }
        let meteorLayers = layers(in: flow).filter { $0.animation(forKey: "meteor") != nil }
        XCTAssertFalse(meteorLayers.isEmpty, "The originally delayed job must actually install its prepared animation")
        let guides = Set(meteorLayers.map(ObjectIdentifier.init))
        for reading in readings.reversed() { flow.update(snapshot: snapshot(reading), animated: false) }
        XCTAssertEqual(runtime.preparationCountForTest, 1)
        XCTAssertEqual(Set(layers(in: flow).filter { $0.animation(forKey: "meteor") != nil }
            .map(ObjectIdentifier.init)), guides, "Small updates must preserve a scheduled natural handoff")
        XCTAssertEqual(runtime.particleLayersForTest.map(ObjectIdentifier.init), identities)

        flow.appearance = NSAppearance(named: .darkAqua)
        flow.update(snapshot: snapshot(readings[0]), animated: false)
        XCTAssertGreaterThan(runtime.preparationCountForTest, 1)
        XCTAssertTrue(layers(in: flow).allSatisfy { $0.animation(forKey: "meteor") == nil },
                      "Old-theme sprite frames must leave immediately, not finish in the wrong appearance")
        flow.setAnimationsEnabled(false)
        var drained = false
        runtime.waitForPreparationsForTest { drained = true }
        waitUntil { drained }
        XCTAssertEqual(animationCount(flow), 0)
        XCTAssertEqual(runtime.cachedFrameBytesForTest, 0)
    }

    func testMixedGuideToleranceIsAnchoredAndLargeDriftStillCancels() {
        let flow = PowerFlowView()
        flow.frame = NSRect(x: 0, y: 0, width: 328, height: 224)
        attachForMotion(flow)
        flow.layoutSubtreeIfNeeded()
        let runtime = flow.fusionParticleLayerForTest
        let started = expectation(description: "Initial preparation is held")
        let release = DispatchSemaphore(value: 0)
        runtime.preparationGateForTest = {
            started.fulfill()
            _ = release.wait(timeout: .now() + 30)
        }
        defer { release.signal(); flow.setAnimationsEnabled(false) }
        flow.update(snapshot: .init(percent: 44, plugged: true, adapterW: 30.1,
            batteryW: -9.65, systemW: 39.75, deviceOutputW: 12.25), animated: false)
        flow.setAnimationsEnabled(true)
        wait(for: [started], timeout: 5)
        runtime.preparationGateForTest = nil
        // Each neighbouring change is tiny; total drift must not roll the reuse
        // baseline forward indefinitely and keep an unrelated old trajectory.
        for step in 1...60 {
            let adapter = 30.1 + Double(step) * 0.2
            flow.update(snapshot: .init(percent: 44, plugged: true, adapterW: adapter,
                batteryW: -9.65, systemW: adapter + 9.65, deviceOutputW: 12.25), animated: false)
        }
        XCTAssertGreaterThan(runtime.preparationCountForTest, 1)
        XCTAssertEqual(flow.nodePresentationsForTest.first?.value, "42.1 W")
        flow.setAnimationsEnabled(false)
        release.signal()
        var drained = false
        runtime.waitForPreparationsForTest { drained = true }
        waitUntil { drained }
        XCTAssertFalse(runtime.pendingPreparationForTest)
        XCTAssertEqual(runtime.cachedFrameBytesForTest, 0)
        XCTAssertEqual(animationCount(flow), 0, "Canceled jobs must not restore old geometry after stop")
    }

    func testStoppingPendingMixedPreparationCannotRestoreAnObsoleteTopology() {
        let mixed = PowerSnapshot(percent: 44, plugged: true, adapterW: 30,
                                  batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2)
        let charging = PowerSnapshot(percent: 72, plugged: true, adapterW: 68,
                                     batteryW: 22.2, systemW: 45.8, deviceOutputW: 7.5)
        let flow = makeFlow(snapshot: mixed)
        defer { flow.setAnimationsEnabled(false) }
        let runtime = flow.fusionParticleLayerForTest
        XCTAssertTrue(runtime.pendingPreparationForTest)
        flow.setAnimationsEnabled(false)
        flow.update(snapshot: charging, animated: false)
        var drained = false
        runtime.waitForPreparationsForTest { drained = true }
        waitUntil { drained }
        XCTAssertEqual(flow.topologyForTest, "adapterOutputSplit")
        XCTAssertFalse(runtime.pendingPreparationForTest)
        XCTAssertTrue(runtime.container.isHidden)
        XCTAssertEqual(animationCount(flow), 0,
                       "A canceled background result must not reinstall live particles after close or a topology change")
        flow.update(snapshot: mixed, animated: false)
        XCTAssertEqual(animationCount(flow), 0)
        XCTAssertFalse(runtime.pendingPreparationForTest)
    }
}
