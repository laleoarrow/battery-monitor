import AppKit

/// A connection-only accent over the USB waiting dash, with no power particles.
final class USBConnectionGlow {
    let container = CALayer()

    private static let travelWidth: CGFloat = 256
    private static let segmentWidth = travelWidth * 0.28
    private let clip = CAShapeLayer()
    private let haloHost = CALayer()
    private let coreHost = CALayer()
    private let haloMask = CAShapeLayer()
    private let coreMask = CAShapeLayer()
    private let haloField = CALayer()
    private let coreField = CALayer()
    private let halo = CAGradientLayer()
    private let core = CAGradientLayer()
    private var configuration: (geometry: PipeGeometry, color: CGColor, bounds: CGRect)?
    private var isRunning = false
#if DEBUG
    private(set) var animationInstallationsForTest = 0
#endif

    init() {
        container.isHidden = true
        container.opacity = 0
        container.mask = clip
        clip.fillColor = NSColor.black.cgColor
        for (host, mask, field, light, width) in [
            (haloHost, haloMask, haloField, halo, CGFloat(5)),
            (coreHost, coreMask, coreField, core, CGFloat(2))
        ] {
            container.addSublayer(host)
            host.mask = mask
            host.addSublayer(field)
            field.anchorPoint = .zero
            field.addSublayer(light)
            mask.fillColor = nil
            mask.strokeColor = NSColor.black.cgColor
            mask.lineWidth = width
            mask.lineCap = .butt
            light.startPoint = CGPoint(x: 0, y: 0.5)
            light.endPoint = CGPoint(x: 1, y: 0.5)
            light.locations = (0...8).map { NSNumber(value: Double($0) / 8) }
        }
    }

    func configure(geometry: PipeGeometry?, color: NSColor, bounds: CGRect,
                   opacity: Float, animated: Bool) {
        guard animated, opacity > 0, let geometry, geometry.end.x > geometry.start.x else {
            stop()
            return
        }
        let resolvedColor = color.cgColor
        let geometryChanged = configuration?.geometry != geometry || configuration?.bounds != bounds
        let colorChanged = configuration?.color != resolvedColor
        PopoverStyle.setWithoutAnimation {
            self.container.isHidden = false
            self.container.opacity = opacity
            if geometryChanged {
                self.container.bounds = bounds
                self.container.position = CGPoint(x: bounds.midX, y: bounds.midY)
                self.clip.bounds = bounds
                self.clip.position = CGPoint(x: bounds.midX, y: bounds.midY)
                self.clip.path = CGPath(rect: CGRect(x: geometry.start.x, y: bounds.minY,
                    width: geometry.end.x - geometry.start.x, height: bounds.height), transform: nil)
                for (host, mask, field, light) in [
                    (self.haloHost, self.haloMask, self.haloField, self.halo),
                    (self.coreHost, self.coreMask, self.coreField, self.core)
                ] {
                    host.bounds = bounds
                    host.position = CGPoint(x: bounds.midX, y: bounds.midY)
                    mask.bounds = bounds
                    mask.position = CGPoint(x: bounds.midX, y: bounds.midY)
                    mask.path = geometry.path
                    // Only the light's reference space scales. The actual
                    // curved masks keep their approved 2pt and 5pt widths.
                    field.bounds = CGRect(x: 0, y: 0, width: Self.travelWidth, height: bounds.height)
                    field.position = CGPoint(x: geometry.start.x, y: bounds.minY)
                    field.transform = CATransform3DMakeScale(
                        (geometry.end.x - geometry.start.x) / Self.travelWidth, 1, 1)
                    light.bounds = CGRect(x: 0, y: 0, width: Self.segmentWidth, height: bounds.height)
                    light.position = CGPoint(x: -Self.segmentWidth / 2, y: bounds.height / 2)
                }
            }
            if colorChanged {
                let falloff: [CGFloat] = [0, 0.04, 0.18, 0.6, 1, 0.6, 0.18, 0.04, 0]
                self.halo.colors = falloff.map { color.withAlphaComponent($0 * 0.06).cgColor }
                self.core.colors = falloff.map { color.withAlphaComponent($0 * 0.42).cgColor }
            }
            if !self.isRunning {
                let now = CACurrentMediaTime()
                for light in [self.halo, self.core] {
                    let travel = CABasicAnimation(keyPath: "position.x")
                    travel.fromValue = -Self.segmentWidth / 2
                    travel.toValue = Self.travelWidth + Self.segmentWidth / 2
                    travel.duration = 3
                    travel.beginTime = light.convertTime(now, from: nil)
                    travel.timingFunction = CAMediaTimingFunction(name: .linear)
                    travel.repeatCount = .infinity
                    travel.isRemovedOnCompletion = false
                    light.add(travel, forKey: "connectionGlow")
#if DEBUG
                    self.animationInstallationsForTest += 1
#endif
                }
                self.isRunning = true
            }
        }
        configuration = (geometry, resolvedColor, bounds)
    }

    func stop() {
        configuration = nil
        isRunning = false
        PopoverStyle.setWithoutAnimation {
            self.core.removeAnimation(forKey: "connectionGlow")
            self.halo.removeAnimation(forKey: "connectionGlow")
            self.container.isHidden = true
            self.container.opacity = 0
        }
    }

#if DEBUG
    var lightLayersForTest: [CAGradientLayer] { [halo, core] }
    var strokeMasksForTest: [CAShapeLayer] { [haloMask, coreMask] }
    var clipForTest: CAShapeLayer { clip }
    func phaseForTest(at now: CFTimeInterval) -> Double? {
        guard let travel = core.animation(forKey: "connectionGlow"), travel.duration > 0 else { return nil }
        let elapsed = (core.convertTime(now, from: nil) - travel.beginTime) * Double(travel.speed) + travel.timeOffset
        let cycles = elapsed / travel.duration
        return cycles - floor(cycles)
    }
#endif
}
