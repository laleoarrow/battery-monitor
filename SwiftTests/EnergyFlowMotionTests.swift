import AppKit
import XCTest
@testable import Wattson

final class EnergyFlowMotionTests: XCTestCase {
    private func makeMotion(counts: [Int]? = nil, hot: [Bool]? = nil,
                            includeFlybys: Bool = true, verticalOffset: CGFloat = 0,
                            adapterWatts: Double = 30,
                            isCancelled: () -> Bool = { false }) -> EnergyFlowMotion? {
        let snapshot = PowerSnapshot(percent: 44, plugged: true, adapterW: adapterWatts,
                                     batteryW: -9.7, systemW: adapterWatts + 9.7, deviceOutputW: 12.2)
        let input = [VisualEncoding.thickness(adapterWatts), VisualEncoding.thickness(9.7)]
        let output = [VisualEncoding.thickness(adapterWatts - 2.5), VisualEncoding.thickness(12.2)]
        let width = min(input.reduce(0, +), output.reduce(0, +))
        func widths(_ values: [CGFloat], _ maximum: CGFloat) -> [CGFloat] {
            let scale = min(1, maximum / values.reduce(0, +))
            return values.map { $0 * scale }
        }
        func centers(_ values: [CGFloat]) -> [CGFloat] { [90 - values[1] / 2, 90 + values[0] / 2] }
        let inputWidths = widths(input, width), outputWidths = widths(output, width), joint = width * 0.68
        let ni = centers(widths(input, joint)), no = centers(widths(output, joint))
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y + verticalOffset) }
        let incoming = (0..<2).map { index in
            let y: CGFloat = index == 0 ? 51 : 129
            return PipeGeometry(start: point(53, y), control1: point(88.5, y),
                                control2: point(110.5, ni[index]), end: point(146, ni[index]))
        }
        let outgoing = (0..<2).map { index in
            let y: CGFloat = index == 0 ? 51 : 129
            return PipeGeometry(start: point(182, no[index]), control1: point(217.5, no[index]),
                                control2: point(239.5, y), end: point(275, y))
        }
        return EnergyFlowMotion(incoming: incoming, outgoing: outgoing, jointWidth: joint,
                                snapshot: snapshot, inputWidths: inputWidths, outputWidths: outputWidths,
                                particleCounts: counts, hot: hot, includeFlybys: includeFlybys,
                                isCancelled: isCancelled)
    }

    func testApprovedFixtureRetainsValidatedThreeDimensionalTrajectory() throws {
        let motion = try XCTUnwrap(makeMotion())
        XCTAssertEqual(motion.particles.count, 10)
        XCTAssertEqual(motion.enhancedParticleIDForTest, 2)
        let audit = motion.audit()
        XCTAssertEqual(audit["passed"] as? Bool, true)
        let enhanced = try XCTUnwrap(audit["enhanced3D"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(enhanced["zMinimum"] as? Double), -8.777511388478702, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(enhanced["zMaximum"] as? Double), 4.488142842752118, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(enhanced["phaseDebt"] as? Double), 0.230647070183459, accuracy: 0.000001)
        XCTAssertGreaterThan(try XCTUnwrap(enhanced["prepClearance"] as? Double), 0.15)
    }

    func testVariableSourceCountsRetainNativeRandomDrawsAndSpeeds() throws {
        let motion = try XCTUnwrap(makeMotion(counts: [3, 2], hot: [true, false], includeFlybys: false))
        XCTAssertEqual(motion.particles.map(\.source), [0, 0, 0, 1, 1])
        for source in 0..<2 {
            var rng = SeededRNG(seed: source == 0 ? 11 : 29)
            let width = VisualEncoding.thickness(source == 0 ? 30 : 9.7)
            for particle in motion.particles.filter({ $0.source == source }) {
                let offset = (rng.nextUnit() * 2 - 1) * width * 0.36
                let radius = (source == 0 ? 1.3 : 0.85) + rng.nextUnit() * (source == 0 ? 1.9 : 1.4)
                let spread = 1.4 + rng.nextUnit() * 1.1
                let delay = rng.nextUnit()
                XCTAssertEqual(particle.offset, offset)
                XCTAssertEqual(particle.size, radius)
                XCTAssertEqual(particle.spread, spread)
                XCTAssertEqual(particle.delay, delay)
                XCTAssertEqual(particle.speed,
                               particle.referenceLength * VisualEncoding.multiplier(39.7) / (2.4 * spread),
                               accuracy: 0.0000001)
                XCTAssertFalse(particle.isComet)
            }
        }
    }

    func testAnimationCyclesRepeatTheSamePhysicalStateWithoutClearingDebt() throws {
        let motion = try XCTUnwrap(makeMotion())
        for particle in motion.particles {
            let cycle = motion.animationCycle(for: particle)
            if particle.id == motion.enhancedParticleIDForTest {
                XCTAssertGreaterThan(cycle.startTime, 0)
                XCTAssertGreaterThan(cycle.duration, 2 * particle.period)
            } else {
                XCTAssertEqual(cycle.startTime, 0)
                XCTAssertEqual(cycle.duration, particle.period)
            }
            for fraction: CGFloat in [0.05, 0.25, 0.55, 0.95] {
                let time = cycle.startTime + cycle.duration * fraction
                let first = motion.sample(particle, age: try XCTUnwrap(motion.age(particle, time: time)))
                let next = motion.sample(particle, age: try XCTUnwrap(motion.age(particle, time: time + cycle.duration)))
                XCTAssertEqual(first.point.x, next.point.x, accuracy: 0.000001)
                XCTAssertEqual(first.point.y, next.point.y, accuracy: 0.000001)
                XCTAssertEqual(first.worldZ, next.worldZ, accuracy: 0.000001)
                XCTAssertEqual(first.opacity, next.opacity, accuracy: 0.000001)
                XCTAssertEqual(first.tailGrowth, next.tailGrowth, accuracy: 0.000001)
            }
        }
    }

    func testTrueReturnEndsTailWhileRearOcclusionKeepsOutsideTailAlive() throws {
        let motion = try XCTUnwrap(makeMotion())
        let particle = motion.particles[try XCTUnwrap(motion.enhancedParticleIDForTest)]
        let behindTime = try XCTUnwrap(motion.reviewTimes["05-behind"])
        let behind = motion.sample(particle, age: try XCTUnwrap(motion.age(particle, time: behindTime)))
        XCTAssertTrue(behind.isExternal)
        XCTAssertLessThan(behind.worldZ, 0)
        XCTAssertGreaterThan(behind.tailStrength, 0.9)
        var checkedInterior = false
        for index in 0...360 {
            let sample = motion.sample(particle, age: try XCTUnwrap(motion.age(particle, time: CGFloat(index) / 60)))
            if !sample.isExternal {
                checkedInterior = true
                XCTAssertEqual(sample.tailStrength, 0)
                XCTAssertEqual(sample.tailGrowth, 0)
            }
        }
        XCTAssertTrue(checkedInterior)
    }

    func testNativeFallbackHasOffsetPathAndConstantPacedSpeed() throws {
        let motion = try XCTUnwrap(makeMotion(includeFlybys: false))
        XCTAssertNil(motion.enhancedParticleIDForTest)
        for particle in motion.particles {
            let path = motion.path(for: particle)
            XCTAssertEqual(path.currentPoint.x, 275, accuracy: 0.000001)
            XCTAssertEqual(path.currentPoint.y, (particle.destination == 0 ? 51 : 129) + particle.offset,
                           accuracy: 0.000001)
            for fraction: CGFloat in [0.2, 0.4, 0.7] {
                let age = particle.period * fraction, delta: CGFloat = 0.0001
                let a = motion.sample(particle, age: age - delta), b = motion.sample(particle, age: age + delta)
                let measured = hypot(b.point.x - a.point.x, b.point.y - a.point.y) / (2 * delta)
                XCTAssertEqual(measured / particle.speed, 1, accuracy: 0.001)
            }
        }
        let unsupported = try XCTUnwrap(makeMotion(verticalOffset: 25))
        XCTAssertTrue(unsupported.particles.allSatisfy { !$0.isComet })
        XCTAssertTrue(try XCTUnwrap(makeMotion(counts: [0, 0])).particles.isEmpty)
    }

    func testCancelledPreparationNeverPublishesPartialCacheEntry() {
        EnergyFlowMotion.resetCacheForTest()
        XCTAssertNil(makeMotion(isCancelled: { true }))
        var calls = 0
        XCTAssertNil(makeMotion(isCancelled: { calls += 1; return calls >= 5 }))
        XCTAssertEqual(EnergyFlowMotion.cacheEntryCountForTest, 0)
        XCTAssertNil(EnergyFlowDepthMask(frontDepth: { _ in 1 }, bounds: CGSize(width: 20, height: 20),
                                        isCancelled: { true }))
    }

    func testConcurrentNativePreparationKeepsCacheBounded() {
        EnergyFlowMotion.resetCacheForTest()
        let lock = NSLock()
        var successes = 0
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            let motion = self.makeMotion(counts: [2, 2], includeFlybys: false, adapterWatts: 20 + Double(index))
            lock.lock()
            if motion?.particles.count == 4 { successes += 1 }
            lock.unlock()
        }
        XCTAssertEqual(successes, 12)
        XCTAssertLessThanOrEqual(EnergyFlowMotion.cacheEntryCountForTest, 4)
    }

    func testColumnDepthSamplerMatchesExactPixelCentreQueriesAndCanCancel() throws {
        let motion = try XCTUnwrap(makeMotion(includeFlybys: false))
        let width: CGFloat = 328, scale: CGFloat = 2
        let sampler = try XCTUnwrap(motion.makePipeFrontDepthSampler(width: width, scale: scale))
        // Every column, with a grid of exact mask row centres through both
        // branches and the common tube, including pixels outside the body.
        for x in 0..<656 {
            for y in stride(from: 0, to: 448, by: 7) {
                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                let expected = motion.pipeFrontDepth(at: point), actual = sampler(point)
                if let expected {
                    XCTAssertEqual(try XCTUnwrap(actual), expected, accuracy: 1e-12)
                } else {
                    XCTAssertNil(actual)
                }
            }
        }
        XCTAssertNil(sampler(CGPoint(x: -0.25, y: 90)))
        XCTAssertNil(sampler(CGPoint(x: width, y: 90)))
        var checks = 0
        XCTAssertNil(motion.makePipeFrontDepthSampler(width: width, isCancelled: {
            checks += 1
            return checks == 12
        }))
        XCTAssertEqual(checks, 12)
    }
}
