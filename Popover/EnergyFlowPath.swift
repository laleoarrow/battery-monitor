import AppKit

/// Arc-length lookup for a sampled path. Callers own wrapping and the clock;
/// distances outside the path clamp to its endpoints.
struct EnergyFlowPath {
    private let points: [CGPoint]
    private let distances: [CGFloat]
    var length: CGFloat { distances.last! }

    init(points: [CGPoint]) {
        precondition(points.count >= 2 && points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        var retained = [points[0]]
        var accumulated: [CGFloat] = [0]
        for point in points.dropFirst() {
            let previous = retained.last!
            let distance = hypot(point.x - previous.x, point.y - previous.y)
            // Joined curve samples commonly repeat their shared endpoint.
            if distance == 0 { continue }
            retained.append(point)
            accumulated.append(accumulated.last! + distance)
        }
        precondition(retained.count >= 2 && accumulated.last!.isFinite)
        self.points = retained
        distances = accumulated
    }

    func point(atDistance distance: CGFloat) -> CGPoint {
        let (index, fraction) = segment(atDistance: distance)
        let start = points[index]
        let end = points[index + 1]
        return CGPoint(x: start.x + (end.x - start.x) * fraction,
                       y: start.y + (end.y - start.y) * fraction)
    }

    func tangent(atDistance distance: CGFloat) -> CGPoint {
        let (index, _) = segment(atDistance: distance)
        let start = points[index]
        let end = points[index + 1]
        let segmentLength = distances[index + 1] - distances[index]
        return CGPoint(x: (end.x - start.x) / segmentLength,
                       y: (end.y - start.y) / segmentLength)
    }

    /// For uniformly parameter-sampled analytic curves, recover the parameter
    /// index while leaving derivatives to the original curve, not LUT chords.
    func sampleIndex(atDistance distance: CGFloat) -> CGFloat {
        let (index, fraction) = segment(atDistance: distance)
        return CGFloat(index) + fraction
    }

    private func segment(atDistance distance: CGFloat) -> (Int, CGFloat) {
        precondition(distance.isFinite)
        let target = min(length, max(0, distance))
        var lower = 0
        var upper = distances.count - 1
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if distances[middle] <= target { lower = middle } else { upper = middle }
        }
        return (lower, (target - distances[lower]) / (distances[upper] - distances[lower]))
    }
}

/// The same four draws, in the same order, as PipeBundle.rebuildParticles.
struct EnergyFlowParticleSeed {
    let offset, radius, spread, delay: CGFloat

    static func make(seed: UInt64, count: Int, thickness: CGFloat,
                     hot: Bool = false) -> [Self] {
        precondition(count >= 0 && thickness.isFinite && thickness >= 0)
        var rng = SeededRNG(seed: seed)
        return (0..<count).map { _ in
            let offset = (rng.nextUnit() * 2 - 1) * thickness * 0.36
            let radius = (hot ? 1.3 : 0.85) + rng.nextUnit() * (hot ? 1.9 : 1.4)
            let spread = 1.4 + rng.nextUnit() * 1.1
            let delay = rng.nextUnit()
            return Self(offset: offset, radius: radius, spread: spread, delay: delay)
        }
    }
}
