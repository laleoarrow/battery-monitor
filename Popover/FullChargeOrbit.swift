import AppKit

/// Two true circular orbits, projected through a camera 70 points from the
/// centre. Positive depth is in front of the opaque four-point planet.
enum FullChargeOrbitGeometry {
    static let periods: [Double] = [8, 10.6]
    static let planetRadius: CGFloat = 4
    static let tailDuration: Double = 0.52

    struct Sample {
        let point: CGPoint
        let depth: CGFloat
        let scale: CGFloat
    }

    static func project(orbit: Int, angle: Double) -> Sample {
        let radius = orbit == 0 ? 8.4 : 7.4
        let inclination = (orbit == 0 ? 78.0 : 76.0) * .pi / 180
        let roll = (orbit == 0 ? 35.0 : -32.0) * .pi / 180
        let x = radius * cos(angle), y = radius * sin(angle) * cos(inclination)
        let z = radius * sin(angle) * sin(inclination)
        let scale = 70 / (70 - z)
        return Sample(point: CGPoint(x: (x * cos(roll) - y * sin(roll)) * scale,
                                     y: -(x * sin(roll) + y * cos(roll)) * scale),
                      depth: z, scale: scale)
    }

    static func sample(orbit: Int, time: Double) -> Sample {
        let cycle = 2 * Double.pi * time / periods[orbit]
        let phase = orbit == 0 ? Double.pi - 0.35 : 1.45
        let offset = orbit == 0 ? 0.4 : 2.1
        // A small, closed speed variation gives the two stars independent
        // motion without a position or velocity discontinuity at repetition.
        let angle = phase + (orbit == 0 ? 1 : -1)
            * (cycle + 0.06 * (sin(cycle + offset) - sin(offset)))
        return project(orbit: orbit, angle: angle)
    }

    static func ringPath(orbit: Int, front: Bool, center: CGPoint = .zero) -> CGPath {
        let path = CGMutablePath()
        for index in 0...64 {
            let angle = (front ? 0 : Double.pi) + Double(index) / 64 * .pi
            let point = project(orbit: orbit, angle: angle).point
            let translated = CGPoint(x: center.x + point.x, y: center.y + point.y)
            if index == 0 { path.move(to: translated) } else { path.addLine(to: translated) }
        }
        return path
    }

    static func trailPath(orbit: Int, time: Double, front: Bool,
                          center: CGPoint = .zero) -> CGPath {
        let headDepth = sample(orbit: orbit, time: time).depth
        let tailDepth = sample(orbit: orbit, time: time - tailDuration).depth
        let headIsFront = headDepth >= 0
        let tailIsFront = tailDepth >= 0
        var start = 0.0, end = tailDuration
        if headIsFront != tailIsFront {
            var low = 0.0, high = tailDuration
            for _ in 0..<24 {
                let middle = (low + high) / 2
                if (sample(orbit: orbit, time: time - middle).depth >= 0) == headIsFront {
                    low = middle
                } else {
                    high = middle
                }
            }
            if headIsFront == front { end = (low + high) / 2 }
            else { start = (low + high) / 2 }
        } else if headIsFront != front {
            // Collapse at the end nearest the plane, keeping a disappearing
            // fragment local to its last visible position.
            start = abs(headDepth) < abs(tailDepth) ? 0 : tailDuration
            end = start
        }

        // Both sides always have the same path topology. An absent side is a
        // zero-area cross-section, so CA never interpolates a bridge through
        // the planet. Width and colour fade along a continuous ribbon.
        var left: [CGPoint] = [], right: [CGPoint] = []
        for index in 0...24 {
            let age = start + (end - start) * Double(index) / 24
            let point = sample(orbit: orbit, time: time - age)
            let before = sample(orbit: orbit, time: time - age - 0.001).point
            let after = sample(orbit: orbit, time: time - age + 0.001).point
            let dx = after.x - before.x, dy = after.y - before.y
            let length = hypot(dx, dy)
            let halfWidth = 0.275 * pow(max(0, 1 - age / tailDuration), 1.4) * point.scale
            let nx = -dy / length * halfWidth, ny = dx / length * halfWidth
            left.append(CGPoint(x: center.x + point.point.x + nx, y: center.y + point.point.y + ny))
            right.append(CGPoint(x: center.x + point.point.x - nx, y: center.y + point.point.y - ny))
        }
        let path = CGMutablePath()
        path.move(to: left[0])
        for point in left.dropFirst() { path.addLine(to: point) }
        for point in right.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// Precomputed presentation-only animation. All moving paths have a fixed
/// command count; Core Animation interpolates them without an application timer.
final class FullChargeOrbit {
    private struct Orbit {
        let backRing = CAShapeLayer()
        let frontRing = CAShapeLayer()
        let backTrail = CAGradientLayer()
        let frontTrail = CAGradientLayer()
        let backMask = CAShapeLayer()
        let frontMask = CAShapeLayer()
        let head = CAGradientLayer()
        let core = CALayer()
        var layers: [CALayer] { [backRing, frontRing, backTrail, frontTrail, head] }
        var animatedLayers: [CALayer] { [backTrail, frontTrail, backMask, frontMask, head] }
    }

    private struct Frame {
        let sample: FullChargeOrbitGeometry.Sample
        let front: CGPath
        let back: CGPath
        let gradientStart: CGPoint
        let gradientEnd: CGPoint
    }

    private let orbits = [Orbit(), Orbit()]
    private var bounds: CGRect = .null
    private var frames: [[Frame]] = []
    private static let animationKey = "full-orbit"

    init(host: CALayer) {
        for (index, orbit) in orbits.enumerated() {
            // At a shared projected position, the larger concentric circle is
            // nearer on the front hemisphere and farther on the back. This
            // ordering also resolves crossings between the two orbital planes.
            let depth = CGFloat(2 - index)
            orbit.backRing.zPosition = -depth
            orbit.backTrail.zPosition = -depth
            orbit.frontRing.zPosition = depth
            orbit.frontTrail.zPosition = depth
            for (side, ring) in [("back", orbit.backRing), ("front", orbit.frontRing)] {
                ring.name = "full-orbit-\(index)-\(side)-ring"
                ring.fillColor = nil
                ring.lineWidth = 0.12
                ring.lineCap = .round
            }
            for (side, trail, mask) in [("back", orbit.backTrail, orbit.backMask),
                                        ("front", orbit.frontTrail, orbit.frontMask)] {
                trail.name = "full-orbit-\(index)-\(side)-trail"
                trail.locations = [0, 0.4, 1]
                trail.mask = mask
                mask.fillColor = NSColor.black.cgColor
            }
            orbit.head.name = "full-orbit-\(index)-head"
            orbit.head.type = .radial
            orbit.head.startPoint = CGPoint(x: 0.5, y: 0.5)
            orbit.head.endPoint = CGPoint(x: 1, y: 1)
            orbit.head.locations = [0, 0.4, 1]
            let radius: CGFloat = index == 0 ? 0.58 : 0.5
            orbit.head.bounds = CGRect(x: 0, y: 0, width: radius * 5, height: radius * 5)
            orbit.core.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            orbit.core.position = CGPoint(x: radius * 2.5, y: radius * 2.5)
            orbit.core.cornerRadius = radius
            orbit.head.addSublayer(orbit.core)
            for layer in orbit.layers { layer.isHidden = true; host.addSublayer(layer) }
        }
    }

    func layout(in rect: CGRect) {
        guard bounds != rect else { return }
        stop()
        bounds = rect
        frames.removeAll()
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        PopoverStyle.setWithoutAnimation {
            for (index, orbit) in self.orbits.enumerated() {
                for layer in [orbit.backRing, orbit.frontRing, orbit.backTrail, orbit.frontTrail] {
                    layer.frame = rect
                }
                orbit.backMask.frame = orbit.backTrail.bounds
                orbit.frontMask.frame = orbit.frontTrail.bounds
                orbit.backRing.path = FullChargeOrbitGeometry.ringPath(orbit: index, front: false, center: center)
                orbit.frontRing.path = FullChargeOrbitGeometry.ringPath(orbit: index, front: true, center: center)
                let frame = self.frame(orbit: index, time: 0)
                orbit.backMask.path = frame.back
                orbit.frontMask.path = frame.front
                for trail in [orbit.backTrail, orbit.frontTrail] {
                    trail.startPoint = frame.gradientStart
                    trail.endPoint = frame.gradientEnd
                }
                orbit.head.position = CGPoint(x: rect.midX + frame.sample.point.x,
                                              y: rect.midY + frame.sample.point.y)
                orbit.head.zPosition = (frame.sample.depth >= 0 ? 1 : -1) * CGFloat(2 - index)
                orbit.head.transform = CATransform3DMakeScale(frame.sample.scale, frame.sample.scale, 1)
            }
        }
    }

    func updateColors(base: NSColor, highContrast: Bool, reduceTransparency: Bool) {
        let color = base.usingColorSpace(.sRGB)!
        let bright = highContrast ? color : color.blended(withFraction: 0.65, of: .white)!
        PopoverStyle.setWithoutAnimation {
            for orbit in self.orbits {
                orbit.backRing.strokeColor = color.withAlphaComponent(highContrast ? 0.55 : 0.20).cgColor
                orbit.frontRing.strokeColor = bright.withAlphaComponent(highContrast ? 0.65 : 0.20).cgColor
                for trail in [orbit.backTrail, orbit.frontTrail] {
                    trail.colors = [bright.withAlphaComponent(0).cgColor,
                                    bright.withAlphaComponent(0.25).cgColor,
                                    bright.withAlphaComponent(highContrast ? 1 : 0.72).cgColor]
                }
                orbit.head.colors = [bright.withAlphaComponent(reduceTransparency || highContrast ? 0 : 0.28).cgColor,
                                     bright.withAlphaComponent(reduceTransparency || highContrast ? 0 : 0.10).cgColor,
                                     bright.withAlphaComponent(0).cgColor]
                orbit.core.backgroundColor = bright.cgColor
            }
        }
    }

    func setVisible(_ visible: Bool) {
        PopoverStyle.setWithoutAnimation {
            for orbit in self.orbits {
                for layer in orbit.layers where layer.isHidden != !visible {
                    layer.isHidden = !visible
                }
            }
        }
        if !visible { stop() }
    }

    func start(at now: CFTimeInterval) {
        guard orbits[0].head.animation(forKey: Self.animationKey) == nil,
              bounds.width > 0, bounds.height > 0 else { return }
        if frames.isEmpty {
            frames = (0..<2).map { orbit in
                (0...128).map { frame(orbit: orbit, time: Double($0) / 128 * FullChargeOrbitGeometry.periods[orbit]) }
            }
        }
        for (index, orbit) in orbits.enumerated() {
            let frames = frames[index]
            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = frames.map {
                NSValue(point: CGPoint(x: bounds.midX + $0.sample.point.x, y: bounds.midY + $0.sample.point.y))
            }
            let depth = CAKeyframeAnimation(keyPath: "zPosition")
            depth.values = frames.map { ($0.sample.depth >= 0 ? 1 : -1) * (2 - index) }
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = frames.map { $0.sample.scale }
            animate([position, depth, scale], layer: orbit.head, orbit: index, at: now)
            for (trail, mask, front) in [(orbit.backTrail, orbit.backMask, false),
                                          (orbit.frontTrail, orbit.frontMask, true)] {
                let path = CAKeyframeAnimation(keyPath: "path")
                path.values = frames.map { front ? $0.front : $0.back }
                animate([path], layer: mask, orbit: index, at: now)
                let start = CAKeyframeAnimation(keyPath: "startPoint")
                start.values = frames.map { NSValue(point: $0.gradientStart) }
                let end = CAKeyframeAnimation(keyPath: "endPoint")
                end.values = frames.map { NSValue(point: $0.gradientEnd) }
                animate([start, end], layer: trail, orbit: index, at: now)
            }
        }
    }

    func stop() {
        for orbit in orbits { for layer in orbit.animatedLayers { layer.removeAllAnimations() } }
    }

    private func frame(orbit: Int, time: Double) -> Frame {
        let sample = FullChargeOrbitGeometry.sample(orbit: orbit, time: time)
        let tail = FullChargeOrbitGeometry.sample(orbit: orbit, time: time - FullChargeOrbitGeometry.tailDuration)
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        return Frame(sample: sample,
                     front: FullChargeOrbitGeometry.trailPath(orbit: orbit, time: time, front: true, center: center),
                     back: FullChargeOrbitGeometry.trailPath(orbit: orbit, time: time, front: false, center: center),
                     gradientStart: CGPoint(x: 0.5 + tail.point.x / bounds.width, y: 0.5 + tail.point.y / bounds.height),
                     gradientEnd: CGPoint(x: 0.5 + sample.point.x / bounds.width, y: 0.5 + sample.point.y / bounds.height))
    }

    private func animate(_ animations: [CAKeyframeAnimation], layer: CALayer,
                         orbit: Int, at now: CFTimeInterval) {
        let duration = FullChargeOrbitGeometry.periods[orbit]
        for animation in animations { animation.duration = duration; animation.calculationMode = .linear }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.repeatCount = .infinity
        group.beginTime = layer.convertTime(now, from: nil)
        layer.add(group, forKey: Self.animationKey)
    }
}
