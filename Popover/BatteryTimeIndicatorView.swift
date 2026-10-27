import AppKit

/// A small source indicator. Its animation is presentation-only: it never
/// schedules sampling or changes the battery estimate.
final class BatteryTimeIndicatorView: NSView {
    enum Status { case system, fallback, calculating, unavailable }

    private(set) var status: Status = .unavailable
    private let planet = CAGradientLayer()
    private let halo = CAGradientLayer()
    private let comet = CALayer()
    private let dust = (0..<7).map { _ in CALayer() }
    private var tint = PopoverStyle.blue
    private var animationsEnabled = false
    private var presentationActive = false

    static func status(for snapshot: PowerSnapshot, degraded: Bool) -> Status {
        guard !degraded else { return .unavailable }
        // An adapter assisted by the battery is a normal Not Charging state.
        if snapshot.state == .mixedSupply {
            return snapshot.batteryTimeEstimateSource == .system ? .system : .fallback
        }
        switch snapshot.batteryTimeEstimate {
        case .remaining(let minutes) where !snapshot.plugged,
             .charging(let minutes) where snapshot.plugged:
            guard let minutes else { return .calculating }
            guard minutes >= 0 else { return .unavailable }
        case .full where snapshot.plugged, .notCharging where snapshot.plugged:
            break
        default:
            return .unavailable
        }
        return snapshot.batteryTimeEstimateSource == .system ? .system : .fallback
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        wantsLayer = true
        layer?.masksToBounds = false
        halo.type = .radial
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        halo.locations = [0, 0.35, 1]
        layer?.addSublayer(halo)
        planet.name = "planet"
        planet.type = .radial
        planet.startPoint = CGPoint(x: 0.3, y: 0.25)
        planet.endPoint = CGPoint(x: 1, y: 1)
        planet.locations = [0, 0.48, 1]
        planet.masksToBounds = true
        layer?.addSublayer(planet)
        comet.name = "comet"
        layer?.addSublayer(comet)
        for particle in dust { layer?.addSublayer(particle) }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Battery time source")
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        PopoverStyle.setWithoutAnimation {
            self.halo.frame = self.bounds
            self.planet.frame = CGRect(x: self.bounds.midX - 4, y: self.bounds.midY - 4, width: 8, height: 8)
            self.planet.cornerRadius = 4
            for (index, particle) in ([self.comet] + self.dust).enumerated() {
                let size = index == 0 ? 1.9 : max(0.45, 1.5 - CGFloat(index) * 0.15)
                particle.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                particle.cornerRadius = size / 2
                particle.position = self.orbitPoint(angle: 0)
                particle.opacity = 0
            }
        }
        syncMotion()
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); syncMotion() }
    override func viewDidHide() { super.viewDidHide(); stopMotion() }
    override func viewDidUnhide() { super.viewDidUnhide(); syncMotion() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func update(snapshot: PowerSnapshot, degraded: Bool) {
        let next = Self.status(for: snapshot, degraded: degraded)
        if next != status { stopMotion(); status = next }
        tint = snapshot.state == .charging ? PopoverStyle.green : PopoverStyle.blue
        let source: String
        switch status {
        case .system: source = "macOS"
        case .fallback:
            switch snapshot.batteryTimeEstimateSource {
            case .batteryGauge: source = "Battery controller"
            case .observedDischarge: source = "Wattson estimate"
            default: source = "Battery reading"
            }
        case .calculating: source = "Calculating"
        case .unavailable: source = "Unavailable"
        }
        let help: String
        switch status {
        case .system: help = "macOS system value. Steady theme light."
        case .fallback: help = "\(source). A fallback reading; slowly breathing theme light."
        case .calculating:
            help = (snapshot.plugged
                ? "Waiting for a usable time-to-full estimate while charging."
                : "Waiting for a usable estimate of remaining battery time.")
                + " Breathing theme light with an orbiting spark."
        case .unavailable:
            help = degraded ? "Battery data could not be read. Red pulse."
                : "A battery time estimate is currently unavailable. Red pulse; monitoring continues."
        }
        setAccessibilityValue(source)
        setAccessibilityHelp(help)
        toolTip = help
        refreshAppearance()
    }

    func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = (status == .unavailable ? PopoverStyle.red : tint).usingColorSpace(.sRGB)!
            let contrast = PopoverStyle.isHighContrast(effectiveAppearance)
            let highlight = color.blended(withFraction: 0.65, of: .white)!
            let shade = color.blended(withFraction: 0.18, of: .black)!
            var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
#if DEBUG
            if let forced = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_TRANSPARENCY"] {
                reduceTransparency = forced == "1"
            }
#endif
            PopoverStyle.setWithoutAnimation {
                self.planet.colors = contrast ? [color.cgColor, color.cgColor, color.cgColor]
                    : [highlight.cgColor, color.cgColor, shade.cgColor]
                self.planet.borderWidth = contrast ? 0.75 : 0
                self.planet.borderColor = NSColor.labelColor.cgColor
                self.halo.colors = [color.withAlphaComponent(0.30).cgColor,
                                    color.withAlphaComponent(0.13).cgColor,
                                    color.withAlphaComponent(0).cgColor]
                self.halo.isHidden = contrast || reduceTransparency
                self.comet.backgroundColor = highlight.cgColor
                for particle in self.dust { particle.backgroundColor = color.cgColor }
            }
        }
        syncMotion()
    }

    func setAnimationsEnabled(_ enabled: Bool) { animationsEnabled = enabled; syncMotion() }
    func setPresentationActive(_ active: Bool) { presentationActive = active; syncMotion() }

    private static var reducesMotion: Bool {
#if DEBUG
        switch ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"] {
        case "1": return true
        case "0": return false
        default: break
        }
#endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func syncMotion() {
        guard animationsEnabled, presentationActive, window?.isVisible == true,
              !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty, !Self.reducesMotion,
              status != .system else { stopMotion(); return }
        // Fixed keys preserve phase across normal two-second telemetry updates.
        if planet.animation(forKey: "breathing") == nil {
            let duration: CFTimeInterval = status == .fallback ? 3.6 : status == .calculating ? 1.8 : 2.4
            let breath = CAKeyframeAnimation(keyPath: "opacity")
            breath.values = [1, 0.48, 1]
            breath.keyTimes = [0, 0.5, 1]
            breath.timingFunctions = [.init(name: .easeInEaseOut), .init(name: .easeInEaseOut)]
            breath.duration = duration
            breath.repeatCount = .infinity
            breath.beginTime = planet.convertTime(CACurrentMediaTime(), from: nil)
            planet.add(breath, forKey: "breathing")
            halo.add(breath, forKey: "breathing")
        }
        if status == .calculating, comet.animation(forKey: "orbit") == nil { startOrbit() }
    }

    private func stopMotion() {
        for item in [planet, halo, comet] + dust { item.removeAllAnimations() }
    }

    private func orbitPoint(angle: CGFloat) -> CGPoint {
        let x = 8.5 * cos(angle), y = 4.6 * sin(angle)
        let tilt: CGFloat = -.pi / 5
        return CGPoint(x: bounds.midX + x * cos(tilt) - y * sin(tilt),
                       y: bounds.midY + x * sin(tilt) + y * cos(tilt))
    }

    private func startOrbit() {
        let now = CACurrentMediaTime()
        for (index, particle) in ([comet] + dust).enumerated() {
            // One inclined lap after a three-second pause, then darkness.
            // The small phase offsets leave a tapered, curved dust trail.
            let angles = (0...64).map { CGFloat($0) / 64 * .pi * 2 - CGFloat(index) * 0.13 }
            let movement = CAKeyframeAnimation(keyPath: "position")
            movement.values = angles.map { NSValue(point: orbitPoint(angle: $0)) }
            movement.beginTime = 3
            movement.duration = 2.8
            movement.calculationMode = .linear
            let depth = CAKeyframeAnimation(keyPath: "zPosition")
            depth.values = angles.map { sin($0) > 0 ? 1 : -1 }
            depth.beginTime = 3
            depth.duration = 2.8
            let visibility = CAKeyframeAnimation(keyPath: "opacity")
            let alpha = index == 0 ? 1 : 0.7 * pow(0.72, Double(index - 1))
            visibility.values = [0, 0, alpha, alpha, 0, 0]
            visibility.keyTimes = [0, 0.375, 0.40, 0.69, 0.725, 1]
            visibility.duration = 8
            let orbit = CAAnimationGroup()
            orbit.animations = [movement, depth, visibility]
            orbit.duration = 8
            orbit.repeatCount = .infinity
            orbit.beginTime = particle.convertTime(now, from: nil)
            particle.add(orbit, forKey: "orbit")
        }
    }
}
