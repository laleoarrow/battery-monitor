import AppKit

/// Particle identity follows a directed source-to-destination journey, even
/// when the source or destination leg collapses into the shared junction.
enum FlowParticleRoute: Int, CaseIterable {
    case adapterSystem, adapterBattery, adapterDevice, batterySystem, batteryDevice

    var input: FlowEdgeRole {
        self == .batterySystem || self == .batteryDevice ? .batteryInput : .adapterInput
    }

    var output: FlowEdgeRole {
        switch self {
        case .adapterSystem, .batterySystem: return .systemOutput
        case .adapterBattery: return .batteryCharge
        case .adapterDevice, .batteryDevice: return .deviceOutput
        }
    }

    static func fusion(source: Int, destination: Int) -> Self {
        source == 0 ? (destination == 0 ? .adapterSystem : .adapterDevice)
            : (destination == 0 ? .batterySystem : .batteryDevice)
    }
}

struct FlowMorphParticleSeed {
    var route: FlowParticleRoute
    var ordinal: Int
    var phase: Double
    var epoch: Double
    var pathLength: CGFloat
    var wallPeriod: Double
    var offset: CGFloat
    var radius: CGFloat
    var color: CGColor
    var shadowColor: CGColor
    var shadowOpacity: Float
    var shadowRadius: CGFloat
    var position: CGPoint
    var opacity: Float = 1

    func phase(at now: Double) -> Double {
        Self.unitPhase(phase + (now - epoch) / wallPeriod)
    }

    static func unitPhase(_ value: Double) -> Double { value - floor(value) }

    static func visibility(at phase: Double) -> Float {
        Float(phase < 0.09 ? phase / 0.09 : phase > 0.86 ? (1 - phase) / 0.14 : 1)
    }
}

/// Only the short structural transition is sampled on the main thread. At
/// rest the original CA particle pools own every particle and no timer remains.
final class FlowMorphParticles {
    let container = CALayer()

    static func preserveOpacity(on layer: CALayer, opacity: Float, phase: Double, now: Double) {
        let difference = opacity - FlowMorphParticleSeed.visibility(at: phase)
        guard abs(difference) > 0.001, phase >= 0, phase < 1,
              let ride = layer.animation(forKey: "ride"), ride.duration > 0, ride.speed > 0 else { return }
        // Retire this correction before the first sink-to-source wrap. A
        // bright positive correction must never bypass the native zero-opacity
        // boundary and make a returning head appear to jump across the pipe.
        let remaining = (1 - phase) * ride.duration / Double(ride.speed)
        let duration = min(0.12 * Double(max(layer.speed, 0.001)), remaining * 0.9)
        let correction = CABasicAnimation(keyPath: "opacity")
        correction.fromValue = difference
        correction.toValue = 0
        correction.isAdditive = true
        correction.beginTime = layer.convertTime(now, from: nil)
        correction.duration = duration
        correction.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(correction, forKey: "morphOpacity")
    }

    static func opacity(of layer: CALayer, phase: Double, now: Double) -> Float {
        let base = FlowMorphParticleSeed.visibility(at: phase)
        guard let correction = layer.animation(forKey: "morphOpacity") as? CABasicAnimation,
              correction.duration > 0, let from = correction.fromValue as? NSNumber else {
            return layer.presentation()?.opacity ?? base
        }
        let progress = (layer.convertTime(now, from: nil) - correction.beginTime) / correction.duration
        guard progress >= 0, progress < 1 else { return base }
        // Match the explicit ease-out correction before CA has published its
        // first presentation tree, including same-run-loop interruptions.
        var lower = 0.0, upper = 1.0
        for _ in 0..<20 {
            let t = (lower + upper) / 2
            let x = 3 * (1 - t) * t * t * 0.58 + t * t * t
            if x < progress { lower = t } else { upper = t }
        }
        let t = (lower + upper) / 2
        let eased = 3 * (1 - t) * t * t + t * t * t
        return min(1, max(0, base + from.floatValue * Float(1 - eased)))
    }

    private struct Particle {
        var seed: FlowMorphParticleSeed
        let layer: CALayer
        let initialWidth: CGFloat
        let initialOpacityDifference: Float
    }
    private var particles: [Particle] = []
    private var routeLengths: [FlowParticleRoute: CGFloat] = [:]
    private var began = 0.0
    #if DEBUG
    private(set) var routePathBuildCountForTest = 0
    #endif

    func begin(seeds: [FlowMorphParticleSeed], scene: PowerFlowScene, now: Double) {
        clear()
        began = now
        var paths: [FlowParticleRoute: RoutePath] = [:]
        PopoverStyle.setWithoutAnimation {
            for original in seeds where original.wallPeriod.isFinite && original.wallPeriod > 0 {
                let path = self.routePath(for: original.route, scene: scene, paths: &paths)
                guard path.path.length > 0, path.width > 0 else { continue }
                // A native pool may own only an input or output leg. Project
                // onto its whole journey, then preserve the original travel
                // rate rather than teleporting it to the same fractional phase.
                var seed = original
                seed.phase = path.path.project(seed.position, offset: seed.offset).phase
                seed.epoch = now
                seed.wallPeriod *= Double(path.path.length / max(0.001, seed.pathLength))
                seed.pathLength = path.path.length
                let dot = CALayer()
                dot.bounds = CGRect(x: 0, y: 0, width: seed.radius * 2, height: seed.radius * 2)
                dot.cornerRadius = seed.radius
                dot.backgroundColor = seed.color
                dot.shadowColor = seed.shadowColor
                dot.shadowOpacity = seed.shadowOpacity
                dot.shadowRadius = seed.shadowRadius
                dot.shadowOffset = .zero
                self.container.addSublayer(dot)
                self.particles.append(Particle(seed: seed, layer: dot,
                    initialWidth: path.width,
                    initialOpacityDifference: original.opacity - FlowMorphParticleSeed.visibility(at: seed.phase)))
            }
        }
        update(scene: scene, now: now, paths: &paths)
    }

    func update(scene: PowerFlowScene, now: Double) {
        #if DEBUG
        routePathBuildCountForTest = 0
        #endif
        routeLengths.removeAll(keepingCapacity: true)
        var paths: [FlowParticleRoute: RoutePath] = [:]
        update(scene: scene, now: now, paths: &paths)
    }

    private func update(scene: PowerFlowScene, now: Double, paths: inout [FlowParticleRoute: RoutePath]) {
        guard !particles.isEmpty else { return }
        let opacityProgress = min(1, max(0, (now - began) / 0.12))
        let opacityWeight = Float(1 - opacityProgress * opacityProgress * (3 - 2 * opacityProgress))
        PopoverStyle.setWithoutAnimation {
            for particle in self.particles {
                let path = self.routePath(for: particle.seed.route, scene: scene, paths: &paths)
                let phase = particle.seed.phase(at: now)
                particle.layer.position = path.path.point(at: phase, offset: particle.seed.offset)
                let visibility = min(1, max(0, FlowMorphParticleSeed.visibility(at: phase)
                    + particle.initialOpacityDifference * opacityWeight))
                // A removed journey retires with its actual narrowing pipe.
                // Direct layer positioning cannot interpolate a backward chord
                // across the invisible end-to-start cycle wrap.
                let widthFraction = min(1, max(0, path.width / particle.initialWidth))
                particle.layer.opacity = path.path.length > 0 ? visibility * Float(widthFraction) : 0
            }
        }
    }

    private func routePath(for route: FlowParticleRoute, scene: PowerFlowScene,
                           paths: inout [FlowParticleRoute: RoutePath]) -> RoutePath {
        if let path = paths[route] { return path }
        let path = RoutePath(scene: scene, route: route)
        paths[route] = path
        routeLengths[route] = path.path.length
        #if DEBUG
        routePathBuildCountForTest += 1
        #endif
        return path
    }

    func currentSeeds(now: Double) -> [FlowMorphParticleSeed] {
        particles.map { particle in
            var seed = particle.seed
            seed.phase = seed.phase(at: now)
            seed.epoch = now
            seed.pathLength = routeLengths[seed.route] ?? seed.pathLength
            seed.position = particle.layer.position
            seed.opacity = particle.layer.opacity
            return seed
        }
    }

    func clear() {
        #if DEBUG
        routePathBuildCountForTest = 0
        #endif
        PopoverStyle.setWithoutAnimation {
            self.particles.forEach { $0.layer.removeAllAnimations(); $0.layer.removeFromSuperlayer() }
            self.container.removeAllAnimations()
            self.particles.removeAll()
            self.routeLengths.removeAll()
        }
    }

    private struct RoutePath {
        let path: FlowParticlePath
        let width: CGFloat

        init(scene: PowerFlowScene, route: FlowParticleRoute) {
            let incoming = scene.edges[route.input.rawValue]
            let outgoing = scene.edges[route.output.rawValue]
            let common = scene.edges[FlowEdgeRole.common.rawValue].geometry
            let bridge = PipeGeometry(start: incoming.geometry.end,
                control1: CGPoint(x: common.control1.x, y: incoming.geometry.end.y),
                control2: CGPoint(x: common.control2.x, y: outgoing.geometry.start.y),
                end: outgoing.geometry.start)
            path = FlowParticlePath(curves: [incoming.geometry, bridge, outgoing.geometry])
            width = max(0, min(incoming.startWidth, outgoing.endWidth))
        }
    }
}

/// A small sampled path shared by native-pool capture and transition handoff.
/// Degenerate legs are valid and add no distance or stationary particle seats.
struct FlowParticlePath {
    private let points: [CGPoint]
    private let distances: [CGFloat]
    let length: CGFloat

    init(curves: [PipeGeometry]) {
        var points: [CGPoint] = [curves.first?.start ?? .zero]
        var distances: [CGFloat] = [0]
        var length: CGFloat = 0
        for curve in curves {
            for index in 1...64 {
                let point = curve.point(at: CGFloat(index) / 64)
                let previous = points[points.count - 1]
                let step = hypot(point.x - previous.x, point.y - previous.y)
                guard step > 0.00001 else { continue }
                length += step
                points.append(point)
                distances.append(length)
            }
        }
        self.points = points
        self.distances = distances
        self.length = length
    }

    func project(_ point: CGPoint, offset: CGFloat) -> (phase: Double, distance: CGFloat) {
        guard length > 0 else { return (0, .infinity) }
        let target = CGPoint(x: point.x, y: point.y - offset)
        var nearest = CGFloat.infinity
        var progress: CGFloat = 0
        for index in 1..<points.count {
            let start = points[index - 1], end = points[index]
            let dx = end.x - start.x, dy = end.y - start.y
            let fraction = min(1, max(0, ((target.x - start.x) * dx + (target.y - start.y) * dy) / (dx * dx + dy * dy)))
            let distance = hypot(target.x - start.x - dx * fraction, target.y - start.y - dy * fraction)
            if distance < nearest {
                nearest = distance
                progress = distances[index - 1] + (distances[index] - distances[index - 1]) * fraction
            }
        }
        return (Double(progress / length), nearest)
    }

    func point(at fraction: Double, offset: CGFloat) -> CGPoint {
        guard length > 0 else { return points[0] }
        let distance = CGFloat(fraction) * length
        var left = 0
        var right = distances.count - 1
        while left + 1 < right {
            let middle = (left + right) / 2
            if distances[middle] < distance { left = middle } else { right = middle }
        }
        let span = distances[right] - distances[left]
        let blend = span > 0 ? (distance - distances[left]) / span : 0
        return CGPoint(x: points[left].x + (points[right].x - points[left].x) * blend,
                       y: points[left].y + (points[right].y - points[left].y) * blend + offset)
    }
}
