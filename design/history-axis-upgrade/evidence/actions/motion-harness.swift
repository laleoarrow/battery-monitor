import AppKit

@main private enum AxisMotionMain {
    static func main() {
        guard CommandLine.arguments.count == 3,
              ["scalar", "frames"].contains(CommandLine.arguments[2]) else { exit(64) }
        Settings.configureForTest(defaults: MemoryDefaults())
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AxisMotionProbe(directory: URL(fileURLWithPath: CommandLine.arguments[1]),
                                       captureFrames: CommandLine.arguments[2] == "frames")
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        Settings.resetTestConfiguration()
    }
}

private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

private final class AxisMotionProbe: NSObject, NSApplicationDelegate {
    private let directory: URL
    private let captureFrames: Bool
    private var window: NSWindow!
    private var background: NSWindow!
    private var fixture: HistoryView!
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var started: TimeInterval = 0
    private var phaseStarted: TimeInterval = 0
    private var phase = -1
    private var tickCount = 0
    private var values: [Double] = []
    private var times: [TimeInterval] = []
    private var samples: [[String: Any]] = []
    private var events: [[String: Any]] = []
    private var recorder: NativeFrameRecorder?
    private var finishing = false
    private var retargeted = false
    private var cancelled = false
    private var tracked: [(time: TimeInterval, value: Double)] = []
    private let names = ["ordinary-scroll", "scale-expansion", "scale-contraction", "interrupted-scale-25", "cancel-presentation", "cancel-motion", "repeated-scroll", "interrupted-scale-50", "interrupted-scale-90", "departing-outlier-contraction", "gradient-alpha-contraction"]
    private let duration: TimeInterval = 1.0

    init(directory: URL, captureFrames: Bool) {
        self.directory = directory
        self.captureFrames = captureFrames
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                reason: "Bounded Wattson native animation verification")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                throw NSError(domain: "AxisMotion", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Guest Reduce Motion enabled; cannot prove animation"])
            }
            NSApp.appearance = NSAppearance(named: .darkAqua)
            let size = NSSize(width: PopoverStyle.contentWidth + 48, height: HistoryView.preferredHeight + 48)
            window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 120, y: 100), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.backgroundColor = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1)
            window.hasShadow = false
            window.contentView = NSView(frame: NSRect(origin: .zero, size: size))
            background = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            background.isReleasedWhenClosed = false
            background.isRestorable = false
            background.backgroundColor = .black
            background.hasShadow = false
            background.orderFrontRegardless()
            window.orderFrontRegardless()
            started = ProcessInfo.processInfo.systemUptime
            timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
            RunLoop.main.add(timer!, forMode: .common)
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.fail("GUI watchdog") }
        } catch { fail(String(describing: error)) }
    }

    func applicationWillTerminate(_ notification: Notification) { cleanup() }

    private func cleanup() {
        timer?.invalidate(); timer = nil
        recorder?.cancel()
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        fixture?.setPresentationActive(false)
        window?.close(); background?.close()
    }

    private func fail(_ message: String) {
        fputs("AXIS_MOTION_FAILED: \(message)\n", stderr)
        cleanup()
        exit(1)
    }

    private func update() {
        fixture.update(samples: values, peak: values.max() ?? 0, color: .systemBlue,
                       timing: HistoryChartTiming(sampledAt: times, referenceTime: times.last!))
        CATransaction.flush()
        events.append(["phase": names[phase], "event": "update", "elapsed": ProcessInfo.processInfo.systemUptime - phaseStarted,
                       "ceiling": fixture.chartCeilingForTest, "values": values, "times": times,
                       "hasChartAnimation": fixture.hasChartAnimationForTest, "layers": layerRecords(fixture.layer), "projectedRetainedSamples": projectedSamples(), "interiorAnchors": interiorAnchors(), "headStroke": headStroke()])
    }

    private func append(_ value: Double) {
        if values.count >= 60 { values.removeFirst(); times.removeFirst() }
        values.append(value); times.append((times.last ?? 1000) + 2)
        update()
    }

    private func nextPhase() {
        fixture?.setPresentationActive(false)
        fixture?.removeFromSuperview()
        phase += 1
        guard phase < names.count else { finish(); return }
        fixture = HistoryView()
        fixture.frame = NSRect(x: 24, y: 24, width: PopoverStyle.contentWidth, height: HistoryView.preferredHeight)
        window.contentView!.addSubview(fixture)
        fixture.layoutSubtreeIfNeeded()
        fixture.setAnimationsEnabled(false)
        fixture.setPresentationActive(true)
        values = (0..<60).map { 28 + 5 * sin(Double($0) * 0.4) }
        times = (0..<60).map { 1000 - Double(59 - $0) * 2 }
        phaseStarted = ProcessInfo.processInfo.systemUptime
        retargeted = false; cancelled = false; tracked = []
        if phase == 9 || phase == 10 {
            let ordinary = phase == 9 ? 10.0 : 43.0
            values = [Double](repeating: ordinary, count: 60)
            values[0] = 300; values[3] = 100
            times = (0..<60).map { Double($0) * 2 }
            update()
            for _ in 0..<4 { append(ordinary) } // Reference 126; contraction fires at 128.
        } else if phase == 2 {
            values[0] = 90
            update()
            append(29) // Drop the peak and begin the eight-second contraction hold.
            for _ in 0..<3 { append(29) }
        } else { update() }
        fixture.setAnimationsEnabled(true)
        // Initial visible geometry is committed in an earlier run-loop iteration.
        // The next timer tick performs the measured update.
        tickCount = 0
    }

    @objc private func tick() {
        guard phase >= 0 else {
            if ProcessInfo.processInfo.systemUptime - started > 0.6 { nextPhase() }
            return
        }
        guard phase < names.count else { return }
        tickCount += 1
        if tickCount == 1 { return }
        if tickCount == 2 {
            phaseStarted = ProcessInfo.processInfo.systemUptime
            tracked = Array(zip(times.suffix(3), values.suffix(3))).map { (time: $0.0, value: $0.1) }
            events.append(["phase": names[phase], "event": "before-update", "elapsed": 0,
                           "ceiling": fixture.chartCeilingForTest, "hasChartAnimation": fixture.hasChartAnimationForTest, "layers": layerRecords(fixture.layer),
                           "projectedRetainedSamples": projectedSamples(), "interiorAnchors": interiorAnchors(), "headStroke": headStroke()])
            if captureFrames {
                if recorder == nil {
                    let rect = window.convertToScreen(fixture.convert(fixture.bounds, to: nil))
                    guard let screen = window.screen else { fail("No fixture screen"); return }
                    let bounds = NSRect(x: rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
                    recorder = NativeFrameRecorder(directory: directory.appendingPathComponent("recording-frames"),
                        bounds: bounds, foreground: CGWindowID(window.windowNumber), background: CGWindowID(background.windowNumber))
                }
                recorder?.setPhase(names[phase], started: phaseStarted)
            }
            append(phase == 9 ? 10 : (phase == 10 ? 43 : (phase != 6 && (phase == 1 || phase >= 3) ? 90 : 29)))
            return
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - phaseStarted
        let retargetDelay: TimeInterval = phase == 3 ? 0.0875 : (phase == 7 ? 0.175 : (phase == 8 ? 0.315 : 0.12))
        if [3, 6, 7, 8].contains(phase) && !retargeted && elapsed >= retargetDelay {
            retargeted = true
            events.append(["phase": names[phase], "event": "before-retarget", "elapsed": elapsed,
                           "hasChartAnimation": fixture.hasChartAnimationForTest, "layers": layerRecords(fixture.layer), "projectedRetainedSamples": projectedSamples(), "interiorAnchors": interiorAnchors(), "headStroke": headStroke()])
            append(phase == 6 ? 29 : 140)
            return
        }
        if (phase == 4 || phase == 5) && !cancelled && elapsed >= 0.12 {
            cancelled = true
            if phase == 4 { fixture.setPresentationActive(false) }
            else { fixture.setAnimationsEnabled(false) }
            CATransaction.flush()
            events.append(["phase": names[phase], "event": "cancel", "elapsed": elapsed,
                           "hasChartAnimation": fixture.hasChartAnimationForTest, "layers": layerRecords(fixture.layer), "projectedRetainedSamples": projectedSamples(), "interiorAnchors": interiorAnchors(), "headStroke": headStroke()])
        }
        samples.append(["phase": names[phase], "elapsed": elapsed,
                        "ceiling": fixture.chartCeilingForTest, "hasChartAnimation": fixture.hasChartAnimationForTest, "layers": layerRecords(fixture.layer), "projectedRetainedSamples": projectedSamples(), "interiorAnchors": interiorAnchors(), "headStroke": headStroke()])
        if elapsed >= duration { nextPhase() }
    }

    private func layerRecords(_ root: CALayer?, path: String = "root") -> [[String: Any]] {
        guard let layer = root else { return [] }
        let p = layer.presentation()
        let tr = p?.transform ?? layer.transform
        var entry: [String: Any] = ["path": path, "kind": String(describing: type(of: layer)),
            "presentationAvailable": p != nil,
            "modelTransform": [layer.transform.m11, layer.transform.m22, layer.transform.m41, layer.transform.m42],
            "presentationTransform": [tr.m11, tr.m22, tr.m41, tr.m42],
            "modelPosition": [layer.position.x, layer.position.y],
            "presentationPosition": [(p ?? layer).position.x, (p ?? layer).position.y],
            "bounds": [layer.bounds.origin.x, layer.bounds.origin.y, layer.bounds.width, layer.bounds.height],
            "modelFrame": [layer.frame.origin.x, layer.frame.origin.y, layer.frame.width, layer.frame.height],
            "presentationFrame": [(p ?? layer).frame.origin.x, (p ?? layer).frame.origin.y, (p ?? layer).frame.width, (p ?? layer).frame.height],
            "anchorPoint": [layer.anchorPoint.x, layer.anchorPoint.y], "cornerRadius": layer.cornerRadius]
        if let gradient = layer as? CAGradientLayer,
           let live = gradient.presentation(), let root = fixture.layer?.presentation() {
            func bandPoint(_ p: CGPoint) -> CGPoint {
                live.convert(CGPoint(x: live.bounds.minX + p.x * live.bounds.width,
                                     y: live.bounds.minY + p.y * live.bounds.height), to: root)
            }
            let start = bandPoint(live.startPoint), end = bandPoint(live.endPoint)
            entry["modelStartPoint"] = [gradient.startPoint.x, gradient.startPoint.y]
            entry["modelEndPoint"] = [gradient.endPoint.x, gradient.endPoint.y]
            entry["presentationStartPoint"] = [live.startPoint.x, live.startPoint.y]
            entry["presentationEndPoint"] = [live.endPoint.x, live.endPoint.y]
            entry["effectiveBandStart"] = [start.x, start.y]
            entry["effectiveBandEnd"] = [end.x, end.y]
            if let sample = projectedSamples().dropFirst().first,
               let y = sample["y"] as? CGFloat, end.y != start.y {
                let progress = min(max((y - start.y) / (end.y - start.y), 0), 1)
                entry["retainedSampleAlphaEstimate"] = (0.38 + (0.03 - 0.38) * Double(progress)) * Double(live.opacity)
                entry["alphaEstimateBasis"] = "Production endpoint alphas .38/.03, linear position in actual presentation band; not composited-pixel alpha"
            }
        }
        entry["animations"] = (layer.animationKeys() ?? []).compactMap { key -> [String: Any]? in
            guard let a = layer.animation(forKey: key) else { return nil }
            var record: [String: Any] = ["key": key, "duration": a.duration, "beginTime": a.beginTime]
            if let basic = a as? CABasicAnimation {
                record["keyPath"] = basic.keyPath ?? ""
                if let v = basic.fromValue as? NSNumber { record["fromValue"] = v.doubleValue }
                if let v = basic.toValue as? NSNumber { record["toValue"] = v.doubleValue }
            }
            if let keyframe = a as? CAKeyframeAnimation { record["keyPath"] = keyframe.keyPath ?? "" }
            return record
        }
        return [entry] + (layer.sublayers ?? []).enumerated().flatMap { layerRecords($0.element, path: path + "/" + String($0.offset)) }
            + (layer.mask.map { layerRecords($0, path: path + "/mask") } ?? [])
    }

    private struct StrokeCubic {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
        func point(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u*u*u*start.x + 3*u*u*t*control1.x + 3*u*t*t*control2.x + t*t*t*end.x,
                           y: u*u*u*start.y + 3*u*u*t*control1.y + 3*u*t*t*control2.y + t*t*t*end.y)
        }
    }

    private func allLayers(_ root: CALayer?) -> [CALayer] {
        guard let root else { return [] }
        return [root] + (root.sublayers ?? []).flatMap(allLayers)
            + (root.mask.map { allLayers($0) } ?? [])
    }

    private func stroke() -> CAShapeLayer? {
        allLayers(fixture.layer).compactMap({ $0 as? CAShapeLayer }).first { $0.strokeColor != nil }
    }

    private func cubics(_ path: CGPath?) -> [StrokeCubic] {
        guard let path else { return [] }
        var result: [StrokeCubic] = [], start: CGPoint = .zero
        path.applyWithBlock { pointer in
            let e = pointer.pointee
            switch e.type {
            case .moveToPoint: start = e.points[0]
            case .addCurveToPoint:
                result.append(StrokeCubic(start: start, control1: e.points[0], control2: e.points[1], end: e.points[2]))
                start = e.points[2]
            case .addLineToPoint: start = e.points[0]
            default: break
            }
        }
        return result
    }

    private func targetX(_ timestamp: TimeInterval) -> CGFloat {
        CGFloat(1 - ((times.last ?? 0) - timestamp) / HistoryChartTiming.window) * PopoverStyle.contentWidth
    }

    private func projectedSamples() -> [[String: Any]] {
        guard let line = stroke(), let live = line.presentation(), let root = fixture.layer?.presentation() else { return [] }
        let target = cubics(line.path), shown = cubics(live.path)
        guard target.count == shown.count else { return [] }
        return tracked.compactMap { item in
            let x = targetX(item.time)
            var point: CGPoint?
            for (i, segment) in target.enumerated() {
                if abs(segment.start.x - x) < 0.001 { point = shown[i].start; break }
                if abs(segment.end.x - x) < 0.001 { point = shown[i].end; break }
            }
            guard let point else { return nil }
            let actual = live.convert(point, to: root)
            return ["sampledAt": item.time, "watts": item.value, "x": actual.x, "y": actual.y]
        }
    }

    private func interiorAnchors() -> [[String: Any]] {
        guard tracked.count == 3, let line = stroke(), let live = line.presentation(),
              let root = fixture.layer?.presentation() else { return [] }
        let target = cubics(line.path), shown = cubics(live.path)
        guard target.count == shown.count else { return [] }
        return zip(tracked, tracked.dropFirst()).compactMap { left, right in
            guard let index = target.firstIndex(where: { abs($0.start.x - targetX(left.time)) < 0.001
                && abs($0.end.x - targetX(right.time)) < 0.001 }) else { return nil }
            let actual = live.convert(shown[index].point(0.5), to: root)
            return ["sampledAtMidpoint": (left.time + right.time) / 2, "x": actual.x, "y": actual.y]
        }
    }

    private func headStroke() -> [String: Any] {
        guard let line = stroke(), let live = line.presentation(), let root = fixture.layer?.presentation(),
              let head = allLayers(fixture.layer).first(where: { abs($0.cornerRadius - 2.6) < 0.001 }),
              let liveHead = head.presentation() else { return [:] }
        let center = liveHead.convert(CGPoint(x: liveHead.bounds.midX, y: liveHead.bounds.midY), to: root)
        let local = root.convert(center, to: live)
        let segments = cubics(live.path)
        guard let segment = segments.first(where: { local.x >= $0.start.x - 0.001 && local.x <= $0.end.x + 0.001 }),
              segment.end.x > segment.start.x else { return [:] }
        let t = min(max((local.x - segment.start.x) / (segment.end.x - segment.start.x), 0), 1)
        let onCurve = live.convert(segment.point(t), to: root)
        return ["head": [center.x, center.y], "stroke": [onCurve.x, onCurve.y],
                "deviationPoints": abs(center.y - onCurve.y), "modelLineWidth": line.lineWidth,
                "presentationLineWidth": live.lineWidth,
                "presentationLineTransform": [live.transform.m11, live.transform.m22, live.transform.m41, live.transform.m42]]
    }

    private func finish() {
        guard !finishing else { return }
        finishing = true
        timer?.invalidate(); timer = nil
        if let recorder {
            recorder.stop { [weak self] records, error in
                guard let self else { return }
                if let error { self.fail(error); return }
                self.save(frameRecords: records)
            }
        } else { save(frameRecords: []) }
    }

    private func save(frameRecords: [[String: Any]]) {
        do {
            let record: [String: Any] = ["schema": 1, "mode": captureFrames ? "frames" : "scalar",
                "source": "Unmodified production HistoryView, real NSWindow and NSApplication.run",
                "timerSeconds": 1.0 / 60.0, "PNGWorkDuringScalarPass": false,
                "frameCaptureRunsOffMainThread": true, "scopedLatencyCriticalActivity": true, "frames": frameRecords,
                "samples": samples, "events": events,
                "duration": ProcessInfo.processInfo.systemUptime - started]
            let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("axis-motion.json"), options: .atomic)
            print("AXIS_MOTION_CAPTURE_COMPLETED \(captureFrames ? "frames" : "scalar") samples=\(samples.count)")
            cleanup(); NSApp.terminate(nil)
        } catch { fail(String(describing: error)) }
    }
}


/// CG capture and encoding remain off the AppKit event thread. The scalar pass
/// never creates this recorder. Only this probe's two exact window IDs are read.
private final class NativeFrameRecorder {
    private let directory: URL
    private let bounds: CGRect
    private let foreground: CGWindowID
    private let background: CGWindowID
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "wattson.axis.native-recording", qos: .userInitiated)
    private var phase: (name: String, started: TimeInterval)?
    private var stopping = false
    private var completion: (([[String: Any]], String?) -> Void)?
    private var result: (frames: [[String: Any]], failure: String?)?

    init(directory: URL, bounds: CGRect, foreground: CGWindowID, background: CGWindowID) {
        self.directory = directory; self.bounds = bounds
        self.foreground = foreground; self.background = background
        queue.async { [self] in record() }
    }

    func setPhase(_ name: String, started: TimeInterval) {
        lock.lock(); phase = (name, started); lock.unlock()
    }

    func cancel() { lock.lock(); stopping = true; lock.unlock() }

    func stop(completion: @escaping ([[String: Any]], String?) -> Void) {
        lock.lock()
        self.completion = completion
        stopping = true
        let finished = result
        lock.unlock()
        if let finished { DispatchQueue.main.async { completion(finished.frames, finished.failure) } }
    }

    private func record() {
        var frames: [[String: Any]] = [], failure: String?
        let started = ProcessInfo.processInfo.systemUptime
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            while true {
                lock.lock(); let stopped = stopping, current = phase; lock.unlock()
                if stopped { break }
                let tick = ProcessInfo.processInfo.systemUptime
                if let current {
                    guard let image = WattsonCaptureOwnedWindows(bounds, foreground, background),
                          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                        throw NSError(domain: "AxisRecording", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Own-window recording capture unavailable"])
                    }
                    let completed = ProcessInfo.processInfo.systemUptime
                    lock.lock(); let next = phase; lock.unlock()
                    if next?.name == current.name {
                        let filename = String(format: "frame-%04d.png", frames.count)
                        try png.write(to: directory.appendingPathComponent(filename), options: .atomic)
                        frames.append(["file": filename, "phase": current.name,
                            "elapsedSeconds": completed - started, "phaseElapsedSeconds": completed - current.started,
                            "captureDurationSeconds": completed - tick])
                    }
                }
                let remaining = 1.0 / 30.0 - (ProcessInfo.processInfo.systemUptime - tick)
                if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
            }
        } catch { failure = String(describing: error) }
        lock.lock()
        result = (frames, failure)
        let callback = completion
        lock.unlock()
        let capturedFrames = frames, capturedFailure = failure
        if let callback { DispatchQueue.main.async { callback(capturedFrames, capturedFailure) } }
    }
}
