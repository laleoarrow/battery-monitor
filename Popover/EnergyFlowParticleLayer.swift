import AppKit

/// Prepares only meteor sprites off the main thread. Playback, including ordinary
/// paced particles, remains entirely in Core Animation while the popover is open.
final class EnergyFlowParticleLayer {
    let container = CALayer()
    private static let preparationQueue = DispatchQueue(label: "com.leoarrow.wattson.flow-artwork", qos: .utility)
    private static let frameBudget = 64 * 1024 * 1024
    private let tails = CALayer()
    private var particles: [ParticleLayers] = []
    private var nativeMotion: EnergyFlowMotion?
    private var key: String?
    private var guideAnchor: GuideAnchor?
    private var generation = 0
    private var token: Cancellation?
    private var enabled = false
    private var lastHot = false
    private var preparationCount = 0
    private var animationInstallations = 0

    /// Reuse is anchored to the prepared geometry, never to the previous sample.
    /// The bound covers centreline, radius and seeded offset drift: at most one
    /// Retina pixel. Displayed readings and ordinary rides remain unquantized.
    private struct GuideAnchor {
        let points: [CGPoint]
        let widths, offsets, speeds: [CGFloat]
        let style: String
        let bounds: CGRect

        func accepts(_ other: GuideAnchor) -> Bool {
            guard style == other.style, bounds == other.bounds,
                  points.count == other.points.count, widths.count == other.widths.count,
                  offsets.count == other.offsets.count, speeds.count == other.speeds.count else { return false }
            let centreDrift = zip(points, other.points).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
            let radiusDrift = (zip(widths, other.widths).map { abs($0 - $1) }.max() ?? 0) / 2
            let offsetDrift = zip(offsets, other.offsets).map { abs($0 - $1) }.max() ?? 0
            return centreDrift + radiusDrift + offsetDrift <= 0.5
                && zip(speeds, other.speeds).allSatisfy { abs($0 - $1) <= $0 * 0.01 }
        }
    }

    private final class Cancellation {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }

    private final class Frames {
        let start, duration: Double
        let heads, tails: [CGImage]
        let headRects, tailRects: [CGRect]
        let bytes: Int
        init(start: Double, duration: Double, heads: [CGImage], tails: [CGImage],
             headRects: [CGRect], tailRects: [CGRect], bytes: Int) {
            self.start = start; self.duration = duration
            self.heads = heads; self.tails = tails
            self.headRects = headRects; self.tailRects = tailRects; self.bytes = bytes
        }
    }

    private final class Slot {
        let head = CALayer()
        let tail = CALayer()
        let content = CALayer()
        let tailContent = CALayer()
        init() { head.addSublayer(content); tail.addSublayer(tailContent) }
        var frames: Frames?
        var period: Double = 1
        var origin: Double = 0
        var ordinaryOffset: CGFloat?
        var ordinaryOrdinal: Int?
        var isMeteor: Bool { frames != nil }
        func clear() {
            head.removeAllAnimations(); tail.removeAllAnimations()
            head.removeFromSuperlayer(); tail.removeFromSuperlayer()
            frames = nil
        }
    }

    private final class ParticleLayers {
        let identity: String
        let wrapper = CALayer()
        var particle: EnergyFlowMotion.Particle
        var current: Slot?
        var pending: Slot?
        var handoff = 0.0
        var handoffGeneration = 0
        init(identity: String, particle: EnergyFlowMotion.Particle) {
            self.identity = identity; self.particle = particle
        }
    }

    private final class Completion: NSObject, CAAnimationDelegate {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
            if flag { action() }
        }
    }

    init() {
        tails.anchorPoint = .zero
        container.addSublayer(tails)
    }

    deinit { token?.cancel() }

    /// Export only ordinary heads. Meteor sprites keep their approved clocks
    /// and retire locally instead of rebuilding their guides on every frame.
    func morphSeeds(now: Double) -> [FlowMorphParticleSeed] {
        particles.compactMap { item in
            settle(item, now: now)
            guard let slot = item.current, !slot.isMeteor, slot.period > 0, now >= slot.origin else { return nil }
            let head = slot.content
            let particle = item.particle
            let phase = FlowMorphParticleSeed.unitPhase((now - slot.origin) / slot.period)
            var fallback = nativeMotion?.sample(particle, age: CGFloat(phase) * particle.period).point ?? head.position
            fallback.y += (slot.ordinaryOffset ?? particle.offset) - particle.offset
            let position = head.presentation()?.position ?? fallback
            return FlowMorphParticleSeed(
                route: .fusion(source: particle.source, destination: particle.destination),
                ordinal: slot.ordinaryOrdinal ?? (Int(item.identity.split(separator: ":").last ?? "0") ?? 0),
                phase: phase, epoch: now, pathLength: particle.routeLength, wallPeriod: slot.period,
                offset: slot.ordinaryOffset ?? particle.offset, radius: head.bounds.width / 2,
                color: head.backgroundColor ?? NSColor.white.cgColor,
                shadowColor: head.shadowColor ?? NSColor.white.cgColor,
                shadowOpacity: head.shadowOpacity, shadowRadius: head.shadowRadius, position: position,
                opacity: FlowMorphParticles.opacity(of: head, phase: phase, now: now))
        }
    }

    func retireForMorph() {
        generation += 1
        token?.cancel(); token = nil
        guideAnchor = nil
        let now = CACurrentMediaTime()
        withoutAnimation {
            for item in particles {
                settle(item, now: now)
                discardPending(item)
                item.wrapper.isHidden = item.current?.isMeteor != true
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = container.presentation()?.opacity ?? container.opacity
            fade.toValue = 0
            fade.duration = 0.08
            container.opacity = 0
            container.add(fade, forKey: "morphRetirement")
        }
    }

    func configure(incoming: [PipeGeometry], outgoing: [PipeGeometry], jointWidth: CGFloat,
                   snapshot: PowerSnapshot, inputWidths: [CGFloat], outputWidths: [CGFloat],
                   particleCount: Int, hot: Bool, color: NSColor, bounds: CGRect,
                   animationsEnabled: Bool, handoffSeeds: [FlowMorphParticleSeed]? = nil,
                   handoffTime: Double? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let existingCount = particles.count / 2
        let resolvedCount = particleCount == 0 || existingCount == 0
            || abs(particleCount - existingCount) >= 2 ? particleCount : existingCount
        let resolved = color.usingColorSpace(.sRGB) ?? color
        let dark = PopoverStyle.isDark(NSAppearance.currentDrawing())
        let values = (incoming + outgoing).flatMap {
            [$0.start.x, $0.start.y, $0.control1.x, $0.control1.y,
             $0.control2.x, $0.control2.y, $0.end.x, $0.end.y]
        } + inputWidths + outputWidths + [jointWidth, CGFloat(snapshot.adapterW), CGFloat(snapshot.batteryW),
            bounds.width, bounds.height, resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
        let nextKey = values.map { String(Double($0)) }.joined(separator: ",")
            + ":\(resolvedCount):\(hot):\(dark)"
        withoutAnimation {
            container.removeAnimation(forKey: "morphRetirement")
            container.opacity = 1
            particles.forEach { $0.wrapper.isHidden = false }
            container.frame = bounds
            tails.frame = container.bounds
        }
        if key == nextKey, enabled == animationsEnabled, handoffSeeds == nil { return }
        let changed = key != nextKey
        key = nextKey
        guard let native = EnergyFlowMotion(incoming: incoming, outgoing: outgoing, jointWidth: jointWidth,
            snapshot: snapshot, inputWidths: inputWidths, outputWidths: outputWidths,
            particleCounts: [resolvedCount, resolvedCount], hot: [hot, hot], includeFlybys: false) else {
            stop(); return
        }
        let neckWidths = incoming.map { 2 * abs($0.end.y - 90) }
            + outgoing.map { 2 * abs($0.start.y - 90) }
        let anchor = GuideAnchor(
            points: (incoming + outgoing).flatMap { [$0.start, $0.control1, $0.control2, $0.end] },
            widths: inputWidths + outputWidths + neckWidths + [jointWidth],
            offsets: native.particles.map(\.offset), speeds: native.particles.map(\.speed),
            style: "\(resolvedCount):\(hot):\(dark):\(resolved.redComponent):\(resolved.greenComponent):\(resolved.blueComponent)",
            bounds: bounds)
        let reuseGuide = enabled && animationsEnabled && guideAnchor?.accepts(anchor) == true
        enabled = animationsEnabled
        lastHot = hot
        if !reuseGuide {
            generation += 1
            token?.cancel(); token = nil
            guideAnchor = animationsEnabled ? anchor : nil
        }
        nativeMotion = native
        let now = handoffTime ?? CACurrentMediaTime()
        reconcile(native, now: now, preserveGuide: reuseGuide)
        var available = Dictionary(grouping: handoffSeeds ?? [], by: \.route)
            .mapValues { $0.sorted { $0.ordinal < $1.ordinal } }
        for item in particles {
            settle(item, now: now)
            if handoffSeeds != nil {
                let route = FlowParticleRoute.fusion(source: item.particle.source, destination: item.particle.destination)
                var candidates = available[route] ?? []
                let seed = candidates.isEmpty ? nil : candidates.removeFirst()
                available[route] = candidates
                discardPending(item)
                let reusable = item.current?.isMeteor == false ? item.current : nil
                if reusable == nil { item.current?.clear() }
                let start = now + (seed == nil && animationsEnabled ? Double(item.particle.delay) * 0.12 : 0)
                let slot = makeNative(item.particle, motion: native, now: start,
                    phase: seed.map { $0.phase(at: now) * Double(item.particle.period) } ?? 0,
                    color: resolved, hot: hot, animated: animationsEnabled,
                    handoff: seed, reusing: reusable)
                if seed == nil { slot.content.opacity = 0 }
                if slot.head.superlayer == nil { item.wrapper.addSublayer(slot.head) }
                item.current = slot
            } else if !animationsEnabled {
                discardPending(item)
                item.current?.clear(); item.current = nil
                installNative(item, motion: native, now: now, phase: seedPhase(item.particle),
                              color: resolved, hot: hot, animated: false)
            } else if !reuseGuide || (item.current?.isMeteor != true && item.pending == nil) {
                let phase = item.current.map { modulo(now - $0.origin, $0.period) / $0.period
                    * Double(item.particle.period) } ?? seedPhase(item.particle)
                if changed || item.current == nil || item.current?.content.animation(forKey: "ride") == nil {
                    item.current?.clear(); item.current = nil
                    installNative(item, motion: native, now: now, phase: phase,
                                  color: resolved, hot: hot, animated: true)
                }
            }
        }
        guard animationsEnabled, !reuseGuide, bounds.width > 0, bounds.height > 0 else { return }
        let currentGeneration = generation
        let cancellation = Cancellation()
        token = cancellation
        preparationCount += 1
        let allowance = Self.frameBudget - cachedFrameBytes
#if DEBUG
        let preparationGate = preparationGateForTest
#endif
        Self.preparationQueue.async { [weak self] in
#if DEBUG
            preparationGate?()
#endif
            let cancelled = { cancellation.isCancelled }
            guard let motion = EnergyFlowMotion(incoming: incoming, outgoing: outgoing, jointWidth: jointWidth,
                snapshot: snapshot, inputWidths: inputWidths, outputWidths: outputWidths,
                particleCounts: [resolvedCount, resolvedCount], hot: [hot, hot], isCancelled: cancelled),
                !cancelled() else { return }
            var prepared: [Int: Frames] = [:]
            if motion.particles.contains(where: \.isComet), allowance > 0,
               let sampler = motion.makePipeFrontDepthSampler(width: bounds.width, isCancelled: cancelled),
               let mask = EnergyFlowDepthMask(frontDepth: sampler, bounds: bounds.size,
                                               isCancelled: cancelled) {
                var remaining = allowance
                for particle in motion.particles where particle.isComet {
                    guard !cancelled() else { return }
                    if let frames = Self.prepare(motion: motion, particle: particle, color: resolved,
                                                 dark: dark, hot: hot, mask: mask,
                                                 budget: remaining, cancelled: cancelled) {
                        prepared[particle.id] = frames
                        remaining -= frames.bytes
                    }
                }
            }
            guard !cancelled() else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.enabled, self.generation == currentGeneration,
                      !cancelled() else { return }
                self.token = nil
                self.install(prepared, motion: native, color: resolved, hot: hot)
            }
        }
    }

    private func reconcile(_ motion: EnergyFlowMotion, now: Double, preserveGuide: Bool) {
        var existing = Dictionary(uniqueKeysWithValues: particles.map { ($0.identity, $0) })
        var sourceIndices = [0, 0]
        particles = motion.particles.map { particle in
            let identity = "\(particle.source):\(sourceIndices[particle.source])"
            sourceIndices[particle.source] += 1
            let item = existing.removeValue(forKey: identity) ?? ParticleLayers(identity: identity, particle: particle)
            item.particle = particle
            if item.wrapper.superlayer == nil { container.addSublayer(item.wrapper) }
            item.wrapper.frame = container.bounds
            settle(item, now: now)
            if !preserveGuide {
                discardPending(item)
            }
            return item
        }
        for item in existing.values {
            item.current?.clear(); item.pending?.clear(); item.wrapper.removeFromSuperlayer()
        }
    }

    private func installNative(_ item: ParticleLayers, motion: EnergyFlowMotion, now: Double,
                               phase: Double, color: NSColor, hot: Bool, animated: Bool) {
        let slot = makeNative(item.particle, motion: motion, now: now, phase: phase,
                              color: color, hot: hot, animated: animated)
        item.wrapper.addSublayer(slot.head)
        item.current = slot
    }

    private func makeNative(_ p: EnergyFlowMotion.Particle, motion: EnergyFlowMotion, now: Double,
                            phase: Double, color: NSColor, hot: Bool, animated: Bool,
                            handoff: FlowMorphParticleSeed? = nil, reusing: Slot? = nil) -> Slot {
        let slot = reusing ?? Slot()
        let head = slot.content
        let fraction = phase / Double(p.period)
        slot.period = handoff.map { $0.wallPeriod * Double(p.routeLength / max(0.001, $0.pathLength)) } ?? Double(p.period)
        slot.origin = now - fraction * slot.period
        slot.ordinaryOffset = handoff?.offset ?? p.offset
        slot.ordinaryOrdinal = handoff?.ordinal
        let sample = motion.sample(p, age: CGFloat(phase))
        withoutAnimation {
            head.removeAnimation(forKey: "morphArrival")
            head.removeAnimation(forKey: "morphOpacity")
            if !animated {
                head.removeAnimation(forKey: "ride")
                head.removeAnimation(forKey: "flowVisibility")
            }
            let radius = handoff?.radius ?? p.size
            head.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            head.position = handoff?.position ?? sample.point
            head.cornerRadius = radius
            let ink = hot ? PopoverStyle.saturationParticle : NSColor.white
            head.backgroundColor = ink.cgColor
            head.shadowColor = ink.cgColor
            head.shadowOpacity = hot ? 0.95 : 0.6
            head.shadowRadius = handoff?.shadowRadius ?? (hot ? 4 + p.size * 1.9 : 2 + p.size)
            head.shadowOffset = .zero
            head.opacity = handoff?.opacity ?? Float(sample.opacity)
        }
        if animated {
            let ride = CAKeyframeAnimation(keyPath: "position")
            var shift = CGAffineTransform(translationX: 0, y: (handoff?.offset ?? p.offset) - p.offset)
            ride.path = motion.path(for: p).copy(using: &shift); ride.calculationMode = .paced
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.09, 0.86, 1]
            for animation in [ride, fade] {
                animation.duration = slot.period
                animation.repeatCount = .infinity
                animation.beginTime = now
                animation.timeOffset = modulo(fraction * slot.period, slot.period)
            }
            head.add(ride, forKey: "ride"); head.add(fade, forKey: "flowVisibility")
            if let handoff {
                FlowMorphParticles.preserveOpacity(on: head, opacity: handoff.opacity, phase: fraction, now: now)
            }
            animationInstallations += 1
        }
        return slot
    }

    private func install(_ prepared: [Int: Frames], motion: EnergyFlowMotion, color: NSColor, hot: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let now = CACurrentMediaTime()
        for item in particles { settle(item, now: now) }
        let retirementBoundary = particles.reduce(now) { boundary, item in
            guard let old = item.current, old.isMeteor, prepared[item.particle.id] == nil else { return boundary }
            return max(boundary, old.origin + (floor((now - old.origin) / old.period) + 1) * old.period)
        }
        for item in particles {
            guard let old = item.current else { continue }
            guard prepared[item.particle.id] != nil || old.isMeteor else { continue }
            discardPending(item)
            // A guide starts only at a real entry. Existing meteors finish their
            // natural two-pass cycle, retaining all delay already accumulated.
            let earliest = !old.isMeteor && prepared[item.particle.id] != nil ? retirementBoundary : now
            let handoff = old.origin + (floor((earliest - old.origin) / old.period) + 1) * old.period
            let slot: Slot
            if let frames = prepared[item.particle.id] {
                slot = makeMeteor(frames, begin: handoff)
            } else {
                slot = makeNative(item.particle, motion: motion, now: handoff, phase: 0,
                                  color: color, hot: hot, animated: true)
            }
            item.wrapper.addSublayer(slot.head)
            tails.addSublayer(slot.tail)
            item.pending = slot; item.handoff = handoff
            item.handoffGeneration += 1
            let swapGeneration = item.handoffGeneration
            scheduleVisibility(slot.head, from: 0, to: 1, now: now, at: handoff)
            scheduleVisibility(slot.tail, from: 0, to: 1, now: now, at: handoff)
            let disappear = scheduleVisibility(old.head, from: 1, to: 0, now: now, at: handoff)
            scheduleVisibility(old.tail, from: 1, to: 0, now: now, at: handoff)
            disappear.delegate = Completion { [weak self, weak item] in
                guard let self, let item, item.handoffGeneration == swapGeneration else { return }
                self.settle(item, now: CACurrentMediaTime() + 0.001)
            }
            old.head.add(disappear, forKey: "handoff")
        }
    }

    private func makeMeteor(_ frames: Frames, begin: Double) -> Slot {
        let slot = Slot()
        slot.frames = frames; slot.period = frames.duration; slot.origin = begin
        for (layer, images, rectangles) in [(slot.content, frames.heads, frames.headRects),
                                          (slot.tailContent, frames.tails, frames.tailRects)] {
            layer.anchorPoint = .zero
            layer.contentsScale = 2
            layer.contentsGravity = .resize
            withoutAnimation {
                layer.frame = rectangles[0]
                layer.contents = images[0]
            }
            let contents = CAKeyframeAnimation(keyPath: "contents")
            contents.values = images
            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = rectangles.map { NSValue(point: $0.origin) }
            let bounds = CAKeyframeAnimation(keyPath: "bounds")
            bounds.values = rectangles.map { NSValue(rect: CGRect(origin: .zero, size: $0.size)) }
            let times = (0..<images.count).map { NSNumber(value: Double($0) / Double(images.count - 1)) }
            for animation in [contents, position, bounds] {
                animation.keyTimes = times; animation.calculationMode = .discrete
                animation.duration = frames.duration
            }
            let group = CAAnimationGroup()
            group.animations = [contents, position, bounds]
            group.duration = frames.duration; group.repeatCount = .infinity
            group.beginTime = begin
            layer.add(group, forKey: "meteor")
        }
        animationInstallations += 1
        return slot
    }

    @discardableResult
    private func scheduleVisibility(_ layer: CALayer, from: Float, to: Float,
                                    now: Double, at time: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [from, to]; animation.keyTimes = [0, 1]
        animation.calculationMode = .discrete
        animation.beginTime = now; animation.duration = max(0.001, time - now)
        animation.fillMode = .forwards; animation.isRemovedOnCompletion = false
        withoutAnimation { layer.opacity = to }
        layer.add(animation, forKey: "handoff")
        return animation
    }

    private func settle(_ item: ParticleLayers, now: Double) {
        guard let pending = item.pending, now >= item.handoff else { return }
        withoutAnimation {
            item.current?.clear()
            item.current = pending; item.pending = nil
            pending.head.removeAnimation(forKey: "handoff"); pending.tail.removeAnimation(forKey: "handoff")
            pending.head.opacity = 1; pending.tail.opacity = 1
        }
    }

    private func discardPending(_ item: ParticleLayers) {
        guard item.pending != nil else { return }
        item.handoffGeneration += 1
        withoutAnimation {
            item.pending?.clear(); item.pending = nil
            item.current?.head.removeAnimation(forKey: "handoff")
            item.current?.tail.removeAnimation(forKey: "handoff")
            item.current?.head.opacity = 1; item.current?.tail.opacity = 1
        }
    }

    func stop(preservingStaticDisplay: Bool = true) {
        guard enabled || token != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        generation += 1; enabled = false
        guideAnchor = nil
        if !preservingStaticDisplay { key = nil }
        token?.cancel(); token = nil
        func clearAnimations(_ layer: CALayer) {
            layer.removeAllAnimations(); layer.sublayers?.forEach(clearAnimations)
        }
        for item in particles {
            discardPending(item)
            if !preservingStaticDisplay {
                if item.current?.isMeteor == true { item.current?.clear(); item.current = nil }
                continue
            }
            if let nativeMotion {
                let now = CACurrentMediaTime()
                let phase = item.current.map { modulo(now - $0.origin, $0.period) / $0.period
                    * Double(item.particle.period) } ?? seedPhase(item.particle)
                item.current?.clear(); item.current = nil
                installNative(item, motion: nativeMotion, now: now, phase: phase,
                              color: .white, hot: lastHot, animated: false)
            }
        }
        clearAnimations(container)
    }

    private var cachedFrameBytes: Int {
        var seen = Set<ObjectIdentifier>()
        return particles.reduce(0) { total, item in
            total + [item.current, item.pending].compactMap { $0?.frames }.reduce(0) { sum, frames in
                sum + (seen.insert(ObjectIdentifier(frames)).inserted ? frames.bytes : 0)
            }
        }
    }

    private func seedPhase(_ particle: EnergyFlowMotion.Particle) -> Double {
        Double(particle.delay * particle.referenceLength / particle.speed)
    }
    private func modulo(_ value: Double, _ period: Double) -> Double {
        value - floor(value / period) * period
    }
    private func withoutAnimation(_ work: () -> Void) {
        CATransaction.begin(); CATransaction.setDisableActions(true); work(); CATransaction.commit()
    }

#if DEBUG
    var preparationGateForTest: (() -> Void)?
    var preparationCountForTest: Int { preparationCount }
    var pendingPreparationForTest: Bool { token != nil }
    var animationInstallationsForTest: Int { animationInstallations }
    var particleLayersForTest: [CALayer] { particles.map(\.wrapper) }
    var runtimeCyclesForTest: [Double] { particles.map { ($0.pending ?? $0.current)?.period ?? Double($0.particle.period) } }
    var cachedFrameBytesForTest: Int { cachedFrameBytes }
    var presentedMeteorCountForTest: Int { presentedMeteorSlotsForTest.count }
    var presentedMeteorTailCountForTest: Int {
        presentedMeteorSlotsForTest.filter { slot in
            guard let contents = slot.tailContent.presentation()?.contents else { return false }
            let image = contents as! CGImage
            guard image.bitsPerPixel == 32, let data = image.dataProvider?.data,
                  let bytes = CFDataGetBytePtr(data) else { return false }
            for y in 0..<image.height {
                for x in 0..<image.width where bytes[y * image.bytesPerRow + x * 4 + 3] > 8 { return true }
            }
            return false
        }.count
    }
    private var presentedMeteorSlotsForTest: [Slot] {
        let now = CACurrentMediaTime()
        var visible: [Slot] = []
        for particle in particles {
            for slot in [particle.current, particle.pending].compactMap({ $0 }) {
                if slot.frames != nil && now >= slot.origin,
                   (slot.head.presentation()?.opacity ?? 0) > 0,
                   slot.content.presentation()?.contents != nil {
                    visible.append(slot)
                }
            }
        }
        return visible
    }
    func waitForPreparationsForTest(completion: @escaping () -> Void) {
        Self.preparationQueue.async { DispatchQueue.main.async(execute: completion) }
    }
#endif
}

private extension EnergyFlowParticleLayer {
    struct Tile {
        let frame: CGRect
        let pixels: [UInt8]
        var width: Int { Int((frame.width * 2).rounded()) }
        var height: Int { Int((frame.height * 2).rounded()) }
        var image: CGImage {
            let provider = CGDataProvider(data: Data(pixels) as CFData)!
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        }
    }

    static func tileFrame(_ a: CGPoint, _ b: CGPoint, padding: CGFloat) -> CGRect {
        let x = floor((min(a.x, b.x) - padding) * 2) / 2
        let y = floor((min(a.y, b.y) - padding) * 2) / 2
        return CGRect(x: x, y: y,
            width: ceil((max(a.x, b.x) + padding) * 2) / 2 - x,
            height: ceil((max(a.y, b.y) + padding) * 2) / 2 - y)
    }

    /// Both the depth map and this bitmap use minimum-y as row zero. Applying
    /// alpha directly avoids an implicit CGImage vertical flip at mask time.
    static func paint(frame: CGRect, mask: CGImage? = nil, draw: (CGContext) -> Void) -> Tile {
        let width = Int((frame.width * 2).rounded()), height = Int((frame.height * 2).rounded())
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 2, y: -2)
            context.translateBy(x: -frame.minX, y: -frame.minY)
            draw(context)
            context.flush()
        }
        if let data = mask?.dataProvider?.data, let alpha = CFDataGetBytePtr(data) {
            for index in stride(from: 0, to: pixels.count, by: 4) {
                let amount = Int(alpha[index + 3])
                for component in 0..<4 { pixels[index + component] = UInt8(Int(pixels[index + component]) * amount / 255) }
            }
        }
        return Tile(frame: frame, pixels: pixels)
    }

    static func combine(_ tiles: [Tile]) -> Tile {
        guard let first = tiles.first else { return Tile(frame: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), pixels: [0, 0, 0, 0]) }
        let frame = tiles.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        let width = Int((frame.width * 2).rounded()), height = Int((frame.height * 2).rounded())
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for tile in tiles {
            let x = Int(((tile.frame.minX - frame.minX) * 2).rounded())
            let y = Int(((tile.frame.minY - frame.minY) * 2).rounded())
            for row in 0..<tile.height {
                for column in 0..<tile.width {
                    let source = (row * tile.width + column) * 4
                    let destination = ((row + y) * width + column + x) * 4
                    let remaining = 255 - Int(tile.pixels[source + 3])
                    for component in 0..<4 {
                        pixels[destination + component] = UInt8(min(255,
                            Int(tile.pixels[source + component]) + Int(pixels[destination + component]) * remaining / 255))
                    }
                }
            }
        }
        return Tile(frame: frame, pixels: pixels)
    }

    private static func prepare(motion: EnergyFlowMotion, particle: EnergyFlowMotion.Particle,
                        color: NSColor, dark: Bool, hot: Bool, mask: EnergyFlowDepthMask,
                        budget: Int, cancelled: () -> Bool) -> Frames? {
        let cycle = motion.animationCycle(for: particle)
        let initial = particle.delay * particle.referenceLength / particle.speed
        let normalEntry = particle.period - initial.truncatingRemainder(dividingBy: particle.period)
        let duration = Double(cycle.duration)
        // A zero start can mean the enhanced pair began before this view opened.
        // Recover its true entry, rather than sampling one ordinary period into
        // a longer two-pass cycle and exposing a mid-pipe head at handoff.
        let enhanced = cycle.duration > particle.period * 1.5
        let start = Double(cycle.startTime > 0 ? cycle.startTime : enhanced ? -initial : normalEntry)
        let count = max(2, Int(ceil(duration * 60)))
        var heads: [CGImage] = [], tails: [CGImage] = []
        var headRects: [CGRect] = [], tailRects: [CGRect] = []
        var bytes = 0
        for index in 0..<count {
            guard !cancelled() else { return nil }
            let pair = autoreleasepool { () -> (Tile, Tile) in
                let time = CGFloat(start + duration * Double(index) / Double(count))
                return render(motion: motion, particle: particle, time: time, color: color,
                              dark: dark, hot: hot, mask: mask)
            }
            bytes += pair.0.pixels.count + pair.1.pixels.count
            guard bytes <= budget else { return nil }
            heads.append(pair.0.image); tails.append(pair.1.image)
            headRects.append(pair.0.frame); tailRects.append(pair.1.frame)
        }
        // The closing sample is the same invisible pipe-entry state; the
        // keyframe duration stays the exact physical cycle, not a GIF interval.
        heads.append(heads[0]); tails.append(tails[0])
        headRects.append(headRects[0]); tailRects.append(tailRects[0])
        return Frames(start: start, duration: duration, heads: heads, tails: tails,
                      headRects: headRects, tailRects: tailRects, bytes: bytes)
    }

    static func render(motion: EnergyFlowMotion, particle: EnergyFlowMotion.Particle,
                       time: CGFloat, color: NSColor, dark: Bool, hot: Bool,
                       mask: EnergyFlowDepthMask) -> (Tile, Tile) {
        let age = motion.age(particle, time: time)!
        let sample = motion.sample(particle, age: age)
        let radius = particle.size
        var tailTiles: [Tile] = []
        if sample.tailStrength > 0 {
            let history: CGFloat = 0.13 * sample.tailGrowth
            let widthAtHead = 0.18 + radius * (0.25 + 0.8 * sample.tailGrowth)
            let clearance = radius + widthAtHead / 2
            var farLag = clearance / max(1, hypot(sample.projectedVelocity.x, sample.projectedVelocity.y))
            func distance(_ lag: CGFloat) -> CGFloat {
                let past = motion.sample(particle, age: age - lag).point
                return hypot(sample.point.x - past.x, sample.point.y - past.y)
            }
            while distance(farLag) < clearance { farLag *= 1.5 }
            var nearLag: CGFloat = 0
            for _ in 0..<12 {
                let middle = (nearLag + farLag) / 2
                if distance(middle) < clearance { nearLag = middle } else { farLag = middle }
            }
            for step in 0..<18 {
                let t = CGFloat(step) / 18, next = CGFloat(step + 1) / 18
                let a = motion.sample(particle, age: age - farLag - history * (1 - t))
                let b = motion.sample(particle, age: age - farLag - history * (1 - next))
                let strength = min(sample.tailStrength, min(a.tailStrength, b.tailStrength))
                guard strength > 0 else { continue }
                let flicker = 0.95 + 0.035 * sin(2 * .pi * 3 * time + CGFloat(particle.id) + t * 3)
                    + 0.015 * sin(2 * .pi * 7 * time + CGFloat(particle.id) * 1.7)
                let width = 0.18 + next * radius * (0.25 + 0.8 * sample.tailGrowth)
                let glow = 0.3 + 1.7 * sample.tailGrowth
                let frame = tileFrame(a.point, b.point, padding: width / 2 + glow * 3 + 1)
                let depth = mask.tailMask(frame: frame, from: a.point, to: b.point,
                                          fromZ: a.worldZ, toZ: b.worldZ, radius: width / 2)
                tailTiles.append(paint(frame: frame, mask: depth) { context in
                    context.setStrokeColor(color.withAlphaComponent(strength * flicker * next * next * 0.95).cgColor)
                    context.setLineWidth(width); context.setLineCap(.round)
                    context.setShadow(offset: .zero, blur: glow,
                                      color: color.withAlphaComponent(0.18 * next * strength * sample.tailGrowth).cgColor)
                    context.move(to: a.point); context.addLine(to: b.point); context.strokePath()
                })
            }
        }
        let energy = sample.tailStrength * sample.tailGrowth
        let external = sample.isExternal
        let baseGlow = hot ? 4 + radius * 1.9 : 2 + radius
        let glow = (baseGlow + energy * 3) * (external ? 1 + 0.1 * max(0, sample.depth) : 1)
        let frame = tileFrame(sample.point, sample.point, padding: radius + glow * 3 + 1)
        let depth = external ? mask.headMask(frame: frame, center: sample.point, z: sample.worldZ, radius: radius) : nil
        let baseInk = hot ? PopoverStyle.saturationParticle : NSColor.white
        let ink = dark ? baseInk : baseInk.blended(withFraction: sample.tailStrength, of: color)!
        let glowInk = baseInk.blended(withFraction: energy, of: color)!
        let head = paint(frame: frame, mask: depth) { context in
            context.setAlpha((external ? 1 - 0.15 * max(0, -sample.depth) : 1) * sample.opacity)
            context.setFillColor(ink.cgColor)
            context.setShadow(offset: .zero, blur: glow,
                color: glowInk.withAlphaComponent((hot ? 0.95 : 0.6) + energy * (hot ? 0.05 : 0.1)).cgColor)
            context.fillEllipse(in: CGRect(x: sample.point.x - radius, y: sample.point.y - radius,
                                           width: radius * 2, height: radius * 2))
        }
        return (head, combine(tailTiles))
    }
}
