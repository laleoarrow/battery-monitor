import AppKit
import XCTest
@testable import Wattson

final class FlowMorphParticleTests: XCTestCase {
    func testBridgeCleanupRemovesAnyWindowServerContentTransition() {
        let bridge = FlowMorphParticles()
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.25
        bridge.container.add(transition, forKey: "transition")
        bridge.clear()
        XCTAssertTrue((bridge.container.animationKeys() ?? []).isEmpty)
        XCTAssertTrue((bridge.container.sublayers ?? []).isEmpty)
    }

    private func routeTestScene() -> PowerFlowScene {
        var scene = PowerFlowScene.make(snapshot: PowerSnapshot(percent: 41, plugged: true,
            adapterW: 30, batteryW: -9.7, systemW: 39.7, deviceOutputW: 12.2))
        // Exercise all five directed routes without tying the cache contract
        // to the subset present in any one resting power state.
        scene.edges[FlowEdgeRole.batteryCharge.rawValue].startWidth = 7
        scene.edges[FlowEdgeRole.batteryCharge.rawValue].endWidth = 7
        return scene
    }

    private func referenceRoutePath(scene: PowerFlowScene, route: FlowParticleRoute) -> FlowParticlePath {
        let incoming = scene.edges[route.input.rawValue].geometry
        let outgoing = scene.edges[route.output.rawValue].geometry
        let common = scene.edges[FlowEdgeRole.common.rawValue].geometry
        return FlowParticlePath(curves: [incoming, PipeGeometry(start: incoming.end,
            control1: CGPoint(x: common.control1.x, y: incoming.end.y),
            control2: CGPoint(x: common.control2.x, y: outgoing.start.y), end: outgoing.start), outgoing])
    }

    private func routeTestSeed(scene: PowerFlowScene, route: FlowParticleRoute, ordinal: Int) -> FlowMorphParticleSeed {
        let path = referenceRoutePath(scene: scene, route: route)
        let phase = [0.02, 0.31, 0.91, 0.47, 0.79][ordinal % 5]
        let offset = CGFloat(ordinal % 3) - 1
        return FlowMorphParticleSeed(route: route, ordinal: ordinal, phase: phase,
            epoch: 99.9, pathLength: path.length, wallPeriod: 1.1 + Double(ordinal) * 0.13,
            offset: offset, radius: 1.2, color: NSColor.white.cgColor,
            shadowColor: NSColor.systemBlue.cgColor, shadowOpacity: 0.6, shadowRadius: 3,
            position: path.point(at: phase, offset: offset), opacity: 0.27 + Float(ordinal % 5) * 0.1)
    }

    func testRoutePathsAreBuiltOncePerRequestedRouteIncludingInitialUpdate() {
        let scene = routeTestScene()
        let seed = routeTestSeed(scene: scene, route: .adapterSystem, ordinal: 0)
        let invalid = [Double.nan, .infinity, 0, -1].map { period -> FlowMorphParticleSeed in
            var value = seed
            value.wallPeriod = period
            return value
        }
        let routes: [FlowParticleRoute] = [.batteryDevice, .adapterSystem, .batterySystem, .adapterBattery, .adapterDevice]
        let allRoutes = routes.enumerated().map {
            routeTestSeed(scene: scene, route: $0.element, ordinal: $0.offset)
        }
        let cases: [(seeds: [FlowMorphParticleSeed], count: Int)] = [
            ([], 0), (invalid, 0), ([seed, seed, seed], 1),
            ([allRoutes[0], allRoutes[2], allRoutes[0]], 2), (allRoutes, 5)
        ]
        let bridge = FlowMorphParticles()
        defer { bridge.clear() }
        for item in cases {
            bridge.begin(seeds: item.seeds, scene: scene, now: 100)
            XCTAssertEqual(bridge.routePathBuildCountForTest, item.count)
            bridge.update(scene: scene, now: 100.04)
            XCTAssertEqual(bridge.routePathBuildCountForTest, item.count)
            XCTAssertEqual(bridge.currentSeeds(now: 100.04).map(\.ordinal),
                           item.seeds.filter { $0.wallPeriod.isFinite && $0.wallPeriod > 0 }.map(\.ordinal))
        }
        bridge.clear()
        XCTAssertEqual(bridge.routePathBuildCountForTest, 0)
    }

    func testRapidReverseReentryPreservesCapturedParticleFieldsAndRouteCounts() {
        let sceneA = routeTestScene()
        let sceneB = PowerFlowScene.make(snapshot: PowerSnapshot(percent: 41, plugged: true,
            adapterW: 50, batteryW: 10, systemW: 40, deviceOutputW: 12.2))
        let seeds = [routeTestSeed(scene: sceneA, route: .adapterDevice, ordinal: 3),
                     routeTestSeed(scene: sceneA, route: .adapterSystem, ordinal: 1),
                     routeTestSeed(scene: sceneA, route: .adapterDevice, ordinal: 8)]
        let bridge = FlowMorphParticles()
        defer { bridge.clear() }
        bridge.begin(seeds: seeds, scene: sceneA, now: 100)
        XCTAssertEqual(bridge.routePathBuildCountForTest, 2)
        // Each capture is the currently displayed pose at interruption. The
        // next begin must continue it, including immediate same-time reentry.
        for (scene, now) in [(sceneA, 100.0), (sceneB, 100.02), (sceneA, 100.04),
                             (sceneB, 100.041), (sceneA, 100.042)] {
            bridge.update(scene: scene, now: now)
            XCTAssertEqual(bridge.routePathBuildCountForTest, 2)
            let captured = bridge.currentSeeds(now: now)
            XCTAssertEqual(captured.map(\.ordinal), seeds.map(\.ordinal))
            bridge.begin(seeds: captured, scene: scene, now: now)
            XCTAssertEqual(bridge.routePathBuildCountForTest, 2)
            let resumed = bridge.currentSeeds(now: now)
            XCTAssertEqual(resumed.count, seeds.count)
            XCTAssertEqual(bridge.container.sublayers?.count, seeds.count)
            for (before, after) in zip(captured, resumed) {
                XCTAssertEqual(after.route, before.route)
                XCTAssertEqual(after.ordinal, before.ordinal)
                XCTAssertEqual(after.phase, before.phase, accuracy: 0.000_001)
                XCTAssertEqual(after.epoch, before.epoch)
                XCTAssertEqual(after.wallPeriod, before.wallPeriod, accuracy: 0.000_001)
                XCTAssertEqual(after.phase(at: now + 0.01), before.phase(at: now + 0.01), accuracy: 0.000_001)
                XCTAssertEqual(after.pathLength, before.pathLength, accuracy: 0.000_001)
                XCTAssertEqual(after.position.x, before.position.x, accuracy: 0.000_001)
                XCTAssertEqual(after.position.y, before.position.y, accuracy: 0.000_001)
                XCTAssertEqual(after.opacity, before.opacity, accuracy: 0.000_001)
                XCTAssertEqual(after.offset, before.offset)
                XCTAssertEqual(after.radius, before.radius)
                XCTAssertEqual(after.color, before.color)
                XCTAssertEqual(after.shadowColor, before.shadowColor)
                XCTAssertEqual(after.shadowOpacity, before.shadowOpacity)
                XCTAssertEqual(after.shadowRadius, before.shadowRadius)
            }
        }
    }

    func testBeginRejectsZeroWidthOrLengthRoutesAndEmptyUpdatesSampleNothing() {
        let scene = routeTestScene()
        let seed = routeTestSeed(scene: scene, route: .adapterSystem, ordinal: 1)
        var noInputWidth = scene
        noInputWidth.edges[FlowEdgeRole.adapterInput.rawValue].startWidth = 0
        var noOutputWidth = scene
        noOutputWidth.edges[FlowEdgeRole.systemOutput.rawValue].endWidth = 0
        var noLength = scene
        let point = CGPoint(x: 170, y: 90)
        for index in noLength.edges.indices {
            noLength.edges[index].geometry = PipeGeometry(start: point, control1: point, control2: point, end: point)
        }
        let bridge = FlowMorphParticles()
        defer { bridge.clear() }
        for rejected in [noInputWidth, noOutputWidth, noLength] {
            bridge.begin(seeds: [seed], scene: rejected, now: 100)
            // A valid seed still requests its path before the existing width
            // and length guard rejects it; no empty-pool update requests one.
            XCTAssertEqual(bridge.routePathBuildCountForTest, 1)
            XCTAssertTrue(bridge.currentSeeds(now: 100).isEmpty)
            XCTAssertTrue((bridge.container.sublayers ?? []).isEmpty)
            bridge.update(scene: scene, now: 100.04)
            XCTAssertEqual(bridge.routePathBuildCountForTest, 0)
            XCTAssertTrue(bridge.currentSeeds(now: 100.04).isEmpty)
        }
        bridge.begin(seeds: [seed], scene: scene, now: 100.08)
        XCTAssertEqual(bridge.routePathBuildCountForTest, 1)
        XCTAssertEqual(bridge.currentSeeds(now: 100.08).count, 1)
    }

    func testRetiringCollapsedRoutesStillRebuildForEveryNewPose() {
        let scene = routeTestScene()
        let seeds = FlowParticleRoute.allCases.enumerated().map {
            routeTestSeed(scene: scene, route: $0.element, ordinal: $0.offset)
        }
        let bridge = FlowMorphParticles()
        defer { bridge.clear() }
        bridge.begin(seeds: seeds, scene: scene, now: 100)
        var collapsed = scene
        let point = CGPoint(x: 170, y: 90)
        for index in collapsed.edges.indices {
            collapsed.edges[index].geometry = PipeGeometry(start: point, control1: point, control2: point, end: point)
            collapsed.edges[index].startWidth = 0
            collapsed.edges[index].endWidth = 0
        }
        bridge.update(scene: collapsed, now: 100.04)
        XCTAssertEqual(bridge.routePathBuildCountForTest, 5)
        let retired = bridge.currentSeeds(now: 100.04)
        XCTAssertEqual(retired.count, seeds.count)
        for seed in retired {
            XCTAssertEqual(seed.position, point)
            XCTAssertEqual(seed.pathLength, 0)
            XCTAssertEqual(seed.opacity, 0)
        }
        bridge.update(scene: scene, now: 100.08)
        XCTAssertEqual(bridge.routePathBuildCountForTest, 5)
        XCTAssertTrue(bridge.currentSeeds(now: 100.08).allSatisfy { $0.pathLength > 0 && $0.opacity > 0 })
    }

    func testOnDemandRoutesPreserveBaselinePositionsClocksAndOpacity() {
        let initial = routeTestScene()
        let seeds = FlowParticleRoute.allCases.enumerated().map {
            routeTestSeed(scene: initial, route: $0.element, ordinal: $0.offset)
        }
        let bridge = FlowMorphParticles()
        defer { bridge.clear() }
        bridge.begin(seeds: seeds, scene: initial, now: 100)
        for elapsed in [0.0, 0.04, 0.12, 0.2] {
            var changed = initial
            for index in changed.edges.indices {
                changed.edges[index].geometry.control1.y += CGFloat(elapsed * 70)
                changed.edges[index].geometry.control2.x -= CGFloat(elapsed * 40)
                changed.edges[index].endWidth *= 1 - CGFloat(elapsed * 3)
            }
            if elapsed > 0 { bridge.update(scene: changed, now: 100 + elapsed) }
            let actual = bridge.currentSeeds(now: 100 + elapsed)
            XCTAssertEqual(actual.count, seeds.count)
            XCTAssertEqual(bridge.routePathBuildCountForTest, 5)
            for (original, result) in zip(seeds, actual) {
                let originalPath = referenceRoutePath(scene: initial, route: original.route)
                let phase = originalPath.project(original.position, offset: original.offset).phase
                let period = original.wallPeriod * Double(originalPath.length / max(0.001, original.pathLength))
                let expectedPhase = FlowMorphParticleSeed.unitPhase(phase + elapsed / period)
                let path = referenceRoutePath(scene: changed, route: original.route)
                let position = path.point(at: expectedPhase, offset: original.offset)
                let progress = min(1, max(0, elapsed / 0.12))
                let weight = Float(1 - progress * progress * (3 - 2 * progress))
                let visibility = min(1, max(0, FlowMorphParticleSeed.visibility(at: expectedPhase)
                    + (original.opacity - FlowMorphParticleSeed.visibility(at: phase)) * weight))
                let initialWidth = min(initial.edges[original.route.input.rawValue].startWidth,
                                       initial.edges[original.route.output.rawValue].endWidth)
                let width = min(changed.edges[original.route.input.rawValue].startWidth,
                                changed.edges[original.route.output.rawValue].endWidth)
                XCTAssertEqual(result.route, original.route)
                XCTAssertEqual(result.ordinal, original.ordinal)
                XCTAssertEqual(result.phase, expectedPhase, accuracy: 0.000_001)
                XCTAssertEqual(result.epoch, 100 + elapsed)
                XCTAssertEqual(result.wallPeriod, period, accuracy: 0.000_001)
                XCTAssertEqual(result.pathLength, path.length, accuracy: 0.000_001)
                XCTAssertEqual(result.position.x, position.x, accuracy: 0.000_001)
                XCTAssertEqual(result.position.y, position.y, accuracy: 0.000_001)
                XCTAssertEqual(result.opacity, visibility * Float(min(1, max(0, width / initialWidth))), accuracy: 0.000_001)
                XCTAssertEqual(result.radius, original.radius)
                XCTAssertEqual(result.offset, original.offset)
                XCTAssertEqual(result.color, original.color)
                XCTAssertEqual(result.shadowColor, original.shadowColor)
                XCTAssertEqual(result.shadowOpacity, original.shadowOpacity)
                XCTAssertEqual(result.shadowRadius, original.shadowRadius)
            }
        }
    }

    private let bounds = CGRect(x: 0, y: 0, width: 328, height: 224)
    private let straight = PipeGeometry(start: .zero, control1: CGPoint(x: 30, y: 0),
                                        control2: CGPoint(x: 70, y: 0), end: CGPoint(x: 100, y: 0))

    private func makePipe() -> PipeBundle {
        let pipe = PipeBundle()
        pipe.apply(geometry: straight, thickness: 10, color: .systemBlue,
                   bounds: bounds, animated: false)
        pipe.rebuildParticles(count: 3, thickness: 10, color: .systemBlue, period: 2.4,
                              seed: 11, hot: false, animating: true, topology: "test")
        return pipe
    }

    func testOnePassPipeHandoffReusesHeadsAndPreservesPositionOpacityAndLocalVelocity() throws {
        let pipe = makePipe()
        defer { pipe.stopFlow() }
        let before = pipe.particleLayersForTest
        let installations = pipe.particleRideInstallationsForTest
        let now = CACurrentMediaTime()
        var seeds = pipe.morphSeeds(route: .adapterSystem, now: now)
        for index in seeds.indices {
            seeds[index].opacity = 0.27
            seeds[index].ordinal = 900 + index
            // A whole journey twice this leg's length must enter the local
            // pool at half its period, retaining the same physical travel rate.
            seeds[index].pathLength *= 2
            seeds[index].wallPeriod *= 2
        }
        pipe.rebuildParticles(count: 3, thickness: 10, color: .systemBlue, period: 2.4,
            seed: 11, hot: false, animating: true, topology: "test",
            handoff: (seeds, .adapterSystem, now))
        XCTAssertEqual(pipe.particleRideInstallationsForTest - installations, 3)
        XCTAssertEqual(pipe.particleLayersForTest.map(ObjectIdentifier.init), before.map(ObjectIdentifier.init))
        let exported = pipe.morphSeeds(route: .adapterSystem, now: now)
        XCTAssertEqual(exported.map(\.ordinal), seeds.map(\.ordinal))
        for seed in exported { XCTAssertEqual(seed.opacity, 0.27, accuracy: 0.000_001) }
        for (dot, seed) in zip(pipe.particleLayersForTest, seeds) {
            XCTAssertEqual(dot.position.x, seed.position.x, accuracy: 0.000_001)
            XCTAssertEqual(dot.position.y, seed.position.y, accuracy: 0.000_001)
            XCTAssertEqual(dot.opacity, seed.opacity, accuracy: 0.000_001)
            let ride = try XCTUnwrap(dot.animation(forKey: "ride") as? CAKeyframeAnimation)
            let phase = ride.timeOffset / ride.duration
            let correction = dot.animation(forKey: "morphOpacity") as? CABasicAnimation
            let initialCorrection = (correction?.fromValue as? NSNumber)?.floatValue ?? 0
            XCTAssertEqual(FlowMorphParticleSeed.visibility(at: phase) + initialCorrection,
                           seed.opacity, accuracy: 0.000_001)
            XCTAssertEqual(100 / (ride.duration / Double(dot.speed)),
                           Double(seed.pathLength) / seed.wallPeriod, accuracy: 0.000_001)
            if let correction {
                let remaining = (1 - phase) * ride.duration / Double(dot.speed * ride.speed)
                XCTAssertEqual(correction.duration / Double(dot.speed), min(0.12, remaining * 0.9), accuracy: 0.000_001)
                XCTAssertEqual((correction.toValue as? NSNumber)?.floatValue, 0)
            }
        }
    }

    func testPositiveHandoffOpacityExpiresBeforeShortLocalCycleWrap() throws {
        let pipe = PipeBundle()
        defer { pipe.stopFlow() }
        pipe.apply(geometry: straight, thickness: 10, color: .systemBlue, bounds: bounds, animated: false)
        let now = CACurrentMediaTime()
        let path = FlowParticlePath(curves: [straight])
        let seed = FlowMorphParticleSeed(route: .adapterSystem, ordinal: 7, phase: 0.99,
            epoch: now, pathLength: path.length, wallPeriod: 1, offset: 0, radius: 1,
            color: NSColor.white.cgColor, shadowColor: NSColor.white.cgColor,
            shadowOpacity: 0.6, shadowRadius: 3, position: path.point(at: 0.99, offset: 0), opacity: 1)
        pipe.rebuildParticles(count: 1, thickness: 10, color: .systemBlue, period: 2.4,
            seed: 11, hot: false, animating: true, topology: "test", handoff: ([seed], .adapterSystem, now))
        let dot = try XCTUnwrap(pipe.particleLayersForTest.first)
        let ride = try XCTUnwrap(dot.animation(forKey: "ride"))
        let correction = try XCTUnwrap(dot.animation(forKey: "morphOpacity"))
        XCTAssertEqual(ride.duration / Double(dot.speed), 1, accuracy: 0.000_001)
        XCTAssertLessThan(correction.duration / Double(dot.speed), 0.01)
        XCTAssertEqual(try XCTUnwrap(pipe.morphSeeds(route: .adapterSystem, now: now).first).opacity,
                       1, accuracy: 0.000_001)
        let afterWrap = try XCTUnwrap(pipe.morphSeeds(route: .adapterSystem, now: now + 0.010_001).first)
        XCTAssertLessThan(afterWrap.position.x, 0.001)
        XCTAssertLessThan(afterWrap.opacity, 0.000_2)
        let first = try XCTUnwrap(pipe.morphSeeds(route: .adapterSystem, now: now + 0.02).first)
        let second = try XCTUnwrap(pipe.morphSeeds(route: .adapterSystem, now: now + 0.03).first)
        XCTAssertEqual((second.position.x - first.position.x) / 0.01, 100, accuracy: 0.001)
    }

    func testExplicitEmptyHandoffBirthsAtSourceWithoutRedistributingAVisiblePool() throws {
        let pipe = makePipe()
        defer { pipe.stopFlow() }
        let nativeDurations = pipe.particleLayersForTest.map { $0.animation(forKey: "ride")!.duration }
        let now = CACurrentMediaTime()
        pipe.rebuildParticles(count: 3, thickness: 10, color: .systemBlue, period: 2.4,
            seed: 11, hot: false, animating: true, topology: "test", handoff: ([], .adapterSystem, now))
        XCTAssertTrue(pipe.morphSeeds(route: .adapterSystem, now: now).isEmpty)
        for (index, dot) in pipe.particleLayersForTest.enumerated() {
            let ride = try XCTUnwrap(dot.animation(forKey: "ride") as? CAKeyframeAnimation)
            XCTAssertEqual(dot.position.x, straight.start.x)
            XCTAssertEqual(dot.opacity, 0)
            XCTAssertEqual(ride.timeOffset, 0)
            XCTAssertEqual(ride.duration, nativeDurations[index])
            let delay = (ride.beginTime - dot.convertTime(now, from: nil)) / Double(dot.speed)
            XCTAssertGreaterThanOrEqual(delay, 0)
            XCTAssertLessThanOrEqual(delay, 0.12)
        }
        pipe.stopFlow()
        XCTAssertTrue(pipe.particleLayersForTest.allSatisfy { $0.opacity == 1 })
        XCTAssertTrue(pipe.particleLayersForTest.allSatisfy { $0.position.x > 0 && $0.position.x < 100 })
    }

    func testOnePassFusionReusesNativeSlotsAndHiddenStopDoesNotInstallStaticHeads() throws {
        let runtime = EnergyFlowParticleLayer()
        let gate = DispatchSemaphore(value: 0)
        runtime.preparationGateForTest = { _ = gate.wait(timeout: .now() + 10) }
        defer {
            runtime.stop(preservingStaticDisplay: false)
            gate.signal()
            let drained = expectation(description: "Fusion preparation cancellation drained")
            runtime.waitForPreparationsForTest { drained.fulfill() }
            wait(for: [drained], timeout: 5)
        }
        let snapshot = PowerSnapshot(percent: 41, plugged: true, adapterW: 30, batteryW: -9.7,
                                     systemW: 39.7, deviceOutputW: 12.2)
        let scene = PowerFlowScene.make(snapshot: snapshot)
        func configure(seeds: [FlowMorphParticleSeed]? = nil, now: Double? = nil, animated: Bool = true) {
            runtime.configure(incoming: [scene.edges[0].geometry, scene.edges[1].geometry],
                outgoing: [scene.edges[2].geometry, scene.edges[4].geometry], jointWidth: scene.mixedCommonWidth,
                snapshot: snapshot, inputWidths: [scene.edges[0].startWidth, scene.edges[1].startWidth],
                outputWidths: [scene.edges[2].endWidth, scene.edges[4].endWidth],
                particleCount: 3, hot: false, color: .systemBlue, bounds: bounds,
                animationsEnabled: animated, handoffSeeds: seeds, handoffTime: now)
        }
        func heads() -> [CALayer] {
            runtime.particleLayersForTest.compactMap { $0.sublayers?.first?.sublayers?.first }
        }
        configure()
        runtime.preparationGateForTest = nil
        let before = heads()
        XCTAssertEqual(before.count, 6)
        let installations = runtime.animationInstallationsForTest
        let now = CACurrentMediaTime()
        var seeds = runtime.morphSeeds(now: now)
        XCTAssertEqual(seeds.count, 6)
        for index in seeds.indices { seeds[index].opacity = 0.31 }
        configure(seeds: seeds, now: now)
        XCTAssertEqual(heads().count, 6)
        XCTAssertEqual(heads().map(ObjectIdentifier.init), before.map(ObjectIdentifier.init))
        XCTAssertEqual(runtime.animationInstallationsForTest - installations, 6)
        for seed in runtime.morphSeeds(now: now) { XCTAssertEqual(seed.opacity, 0.31, accuracy: 0.000_001) }
        for head in heads() {
            XCTAssertEqual(head.opacity, 0.31, accuracy: 0.000_001)
            let ride = try XCTUnwrap(head.animation(forKey: "ride") as? CAKeyframeAnimation)
            let correction = head.animation(forKey: "morphOpacity") as? CABasicAnimation
            let initialCorrection = (correction?.fromValue as? NSNumber)?.floatValue ?? 0
            XCTAssertEqual(FlowMorphParticleSeed.visibility(at: ride.timeOffset / ride.duration) + initialCorrection,
                           0.31, accuracy: 0.000_001)
        }
        let settledHeads = heads().map(ObjectIdentifier.init)
        let settledInstallations = runtime.animationInstallationsForTest
        runtime.stop(preservingStaticDisplay: false)
        XCTAssertEqual(runtime.animationInstallationsForTest, settledInstallations)
        XCTAssertEqual(heads().map(ObjectIdentifier.init), settledHeads)
        XCTAssertTrue(heads().allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        configure(animated: false)
        XCTAssertEqual(heads().count, 6)
        XCTAssertTrue(heads().contains { $0.opacity > 0 })
        XCTAssertTrue(heads().allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    }

    func testOnePassRecipientRejectsHeadsOnAnotherLegInsteadOfClampingThemToEndpoint() {
        let pipe = makePipe()
        defer { pipe.stopFlow() }
        let now = CACurrentMediaTime()
        var seeds = pipe.morphSeeds(route: .adapterSystem, now: now)
        for index in seeds.indices { seeds[index].position.x += 200 }
        pipe.rebuildParticles(count: 3, thickness: 10, color: .systemBlue, period: 2.4,
            seed: 11, hot: false, animating: true, topology: "test", handoff: (seeds, .adapterSystem, now))
        XCTAssertTrue(pipe.morphSeeds(route: .adapterSystem, now: now).isEmpty)
        for dot in pipe.particleLayersForTest {
            XCTAssertEqual(dot.animation(forKey: "ride")!.timeOffset, 0)
            XCTAssertEqual(dot.position.x, straight.start.x)
            XCTAssertEqual(dot.opacity, 0)
        }
    }

    func testWholeJourneyRetainsWallPeriodAndExportsLatestLengthAfterGeometryChanges() {
        let snapshot = PowerSnapshot(percent: 72, plugged: true, adapterW: 40,
                                     batteryW: 0, systemW: 40)
        let initial = PowerFlowScene.make(snapshot: snapshot)
        let path = FlowParticlePath(curves: [initial.edges[FlowEdgeRole.systemOutput.rawValue].geometry])
        let seed = FlowMorphParticleSeed(route: .adapterSystem, ordinal: 0, phase: 0.4,
            epoch: 100, pathLength: path.length, wallPeriod: 4, offset: 1, radius: 1,
            color: NSColor.white.cgColor, shadowColor: NSColor.white.cgColor,
            shadowOpacity: 0.6, shadowRadius: 3, position: path.point(at: 0.4, offset: 1))
        let bridge = FlowMorphParticles()
        defer { bridge.clear() }
        bridge.begin(seeds: [seed], scene: initial, now: 100)
        var changed = initial
        changed.edges[FlowEdgeRole.systemOutput.rawValue].geometry.end.x += 20
        bridge.update(scene: changed, now: 100.2)
        let result = bridge.currentSeeds(now: 100.2)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].wallPeriod, 4, accuracy: 0.000_001)
        XCTAssertEqual(result[0].phase, 0.45, accuracy: 0.000_001)
        XCTAssertGreaterThan(result[0].pathLength, seed.pathLength)
        let expected = FlowParticlePath(curves: [changed.edges[FlowEdgeRole.systemOutput.rawValue].geometry])
            .point(at: result[0].phase, offset: 1)
        XCTAssertEqual(result[0].position.x, expected.x, accuracy: 0.001)
        XCTAssertEqual(result[0].position.y, expected.y, accuracy: 0.001)
    }

    func testPartialLegCaptureProjectsOntoJourneyWithoutMovingOffPipe() {
        var snapshot = PowerSnapshot(percent: 41, plugged: true, adapterW: 30,
                                     batteryW: -9.7, systemW: 39.7)
        snapshot.deviceOutputW = 12.2
        let scene = PowerFlowScene.make(snapshot: snapshot)
        let leg = FlowParticlePath(curves: [scene.edges[FlowEdgeRole.adapterInput.rawValue].geometry])
        let seed = FlowMorphParticleSeed(route: .adapterSystem, ordinal: 0, phase: 0.45,
            epoch: 100, pathLength: leg.length, wallPeriod: 4, offset: 1, radius: 1,
            color: NSColor.white.cgColor, shadowColor: NSColor.white.cgColor,
            shadowOpacity: 0.6, shadowRadius: 3, position: leg.point(at: 0.45, offset: 1), opacity: 0.27)
        let bridge = FlowMorphParticles()
        defer { bridge.clear() }
        bridge.begin(seeds: [seed], scene: scene, now: 100)
        let restored = bridge.currentSeeds(now: 100)[0]
        XCTAssertEqual(restored.position.x, seed.position.x, accuracy: 0.001)
        XCTAssertEqual(restored.position.y, seed.position.y, accuracy: 0.001)
        XCTAssertEqual(restored.opacity, seed.opacity, accuracy: 0.000_001)
        XCTAssertEqual(restored.pathLength / CGFloat(restored.wallPeriod),
                       seed.pathLength / CGFloat(seed.wallPeriod), accuracy: 0.000_001)
    }

    func testCollapsedMorphLegPaintsNothingAndGrowingLegIsUnhidden() {
        let pipe = PipeBundle()
        let collapsed = PipeGeometry(start: .zero, control1: .zero, control2: .zero, end: .zero)
        pipe.container.isHidden = true
        pipe.applyMorphPose(pose: FlowEdgePose(geometry: collapsed, startWidth: 20,
                                              endWidth: 20, verticalTaper: 0.5),
                            paint: FlowMorphPaint(color: .systemBlue, themeMix: 0.5), bounds: bounds)
        XCTAssertEqual(pipe.container.opacity, 0)
        pipe.applyMorphPose(pose: FlowEdgePose(geometry: straight, startWidth: 20,
                                              endWidth: 20, verticalTaper: 0.5),
                            paint: FlowMorphPaint(color: .systemBlue, themeMix: 0.5), bounds: bounds)
        XCTAssertFalse(pipe.container.isHidden)
        XCTAssertEqual(pipe.container.opacity, 1)
    }

    func testGradientChangesProfileWithoutLosingItsTravellingPhase() throws {
        let pipe = PipeBundle()
        defer { pipe.stopFlow() }
        pipe.apply(geometry: straight, thickness: 10, color: .systemBlue,
                   bounds: bounds, animated: false)
        pipe.startFlow(multiplier: 1, width: bounds.width)
        let now = CACurrentMediaTime()
        let phase = try XCTUnwrap(pipe.captureFlowPhase(now: now))
        pipe.applyMorphPose(pose: FlowEdgePose(geometry: straight, startWidth: 10,
                                              endWidth: 10, verticalTaper: 0.5),
                            paint: FlowMorphPaint(color: .systemBlue, themeMix: 0.5), bounds: bounds)
        pipe.startFlow(multiplier: 1, width: bounds.width, sharedPhase: phase)
        let after = try XCTUnwrap(pipe.captureFlowPhase(now: now))
        XCTAssertEqual(after.offset, phase.offset, accuracy: 0.000_001)
        let gradient = try XCTUnwrap(pipe.geometryLayersForTest.compactMap { $0 as? CAGradientLayer }.first)
        XCTAssertEqual(gradient.locations?.count, 21)
        pipe.apply(geometry: straight, thickness: 10, color: .systemBlue, bounds: bounds,
                   animated: false, taper: (10, 10), centeredTheme: true)
        XCTAssertEqual(try XCTUnwrap(pipe.captureFlowPhase(now: now)).offset, phase.offset, accuracy: 0.000_001)
    }

    func testFirstSettledMixedCommitKeepsVisibleGradientClockAndBlueField() throws {
        let pipe = PipeBundle()
        defer { pipe.stopFlow() }
        let multiplier: CGFloat = 2.25
        let now = CACurrentMediaTime()
        pipe.applyMorphPose(pose: FlowEdgePose(geometry: straight, startWidth: 10,
                                              endWidth: 10, verticalTaper: 1),
                            paint: FlowMorphPaint(color: .systemBlue, themeMix: 1), bounds: bounds)
        pipe.startFlow(multiplier: multiplier, width: bounds.width,
                       sharedPhase: (time: now - 0.1, offset: 0.2))
        let gradient = try XCTUnwrap(pipe.geometryLayersForTest.compactMap { $0 as? CAGradientLayer }.first)
        let mask = try XCTUnwrap(pipe.geometryLayersForTest[3] as? CAShapeLayer)
        let origin = gradient.beginTime
        let offset = gradient.timeOffset
        let previousFrame = now - 1.0 / 60
        let beforePreviousFrame = gradient.convertTime(previousFrame, from: nil)
        let handoff = try XCTUnwrap(pipe.captureFlowPhase(now: now))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pipe.apply(geometry: straight, thickness: 10, color: .systemBlue, bounds: bounds,
                   animated: false, taper: (10, 10), centeredTheme: true)
        pipe.startFlow(multiplier: multiplier, width: bounds.width, sharedPhase: handoff)
        CATransaction.commit()
        CATransaction.flush()

        // Inspect the first commit, with no run-loop delay or eventual-state
        // retry: the just-rendered frame still belongs to this layer's timeline.
        XCTAssertEqual(gradient.beginTime, origin)
        XCTAssertEqual(gradient.timeOffset, offset)
        XCTAssertEqual(gradient.convertTime(previousFrame, from: nil), beforePreviousFrame, accuracy: 0.000_001)
        XCTAssertLessThan(gradient.beginTime,
                          gradient.superlayer?.convertTime(previousFrame, from: nil) ?? previousFrame)
        XCTAssertEqual(try XCTUnwrap(pipe.captureFlowPhase(now: now)).offset, handoff.offset, accuracy: 0.000_001)
        XCTAssertEqual(gradient.opacity, 1)
        XCTAssertFalse(gradient.isHidden)
        XCTAssertEqual(mask.fillColor?.alpha, 1)
        XCTAssertFalse(try XCTUnwrap(mask.path).isEmpty)
        let colors = try XCTUnwrap(gradient.colors as? [CGColor])
        XCTAssertEqual(colors.count, gradient.locations?.count)
        XCTAssertTrue(colors.contains { color in
            guard let rgb = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else { return false }
            return rgb.alphaComponent > 0.5 && rgb.blueComponent > rgb.redComponent
        })
        let later = try XCTUnwrap(pipe.captureFlowPhase(now: now + 0.02))
        XCTAssertEqual(later.offset - handoff.offset, 0.02 * Double(multiplier), accuracy: 0.000_001)
    }

    func testSharedGradientSpeedChangeNearWrapKeepsUnwrappedTimeAndActivationOrigin() throws {
        let pipe = PipeBundle()
        defer { pipe.stopFlow() }
        let now = CACurrentMediaTime()
        let period = VisualEncoding.motionPeriod
        pipe.apply(geometry: straight, thickness: 10, color: .systemBlue, bounds: bounds,
                   animated: false, taper: (10, 10), centeredTheme: true)
        pipe.startFlow(multiplier: 2, width: bounds.width,
                       sharedPhase: (time: now - 5 * period / 2, offset: 0.000_01))
        let gradient = try XCTUnwrap(pipe.geometryLayersForTest.compactMap { $0 as? CAGradientLayer }.first)
        let phase = try XCTUnwrap(pipe.captureFlowPhase(now: now))
        let origin = gradient.beginTime
        let local = gradient.convertTime(now, from: nil)
        XCTAssertGreaterThan(local, 1 + 4 * period)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pipe.startFlow(multiplier: 2.5, width: bounds.width,
                       sharedPhase: (time: now, offset: phase.offset + 3 * period))
        CATransaction.commit()
        CATransaction.flush()

        XCTAssertEqual(gradient.beginTime, origin)
        XCTAssertEqual(gradient.convertTime(now, from: nil), local, accuracy: 0.000_001)
        XCTAssertEqual(gradient.speed, 2.5)
        XCTAssertGreaterThan(gradient.convertTime(now - 1.0 / 60, from: nil),
                             try XCTUnwrap(gradient.animation(forKey: "flow")).beginTime)
        XCTAssertLessThan(gradient.beginTime,
                          gradient.superlayer?.convertTime(now - 1.0 / 60, from: nil) ?? now)
        XCTAssertEqual(try XCTUnwrap(pipe.captureFlowPhase(now: now)).offset, phase.offset, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(pipe.captureFlowPhase(now: now + 0.02)).offset - phase.offset,
                       0.05, accuracy: 0.000_001)
    }
}
