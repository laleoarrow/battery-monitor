import AppKit
import Darwin

@main
private enum Entry {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let defaults = MemoryDefaults()
        Settings.configureForTest(defaults: defaults)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        app.activate(ignoringOtherApps: true)
        do {
            try Probe(URL(fileURLWithPath: CommandLine.arguments[1])).run()
            Settings.resetTestConfiguration()
        } catch {
            fputs("HISTORY_PROBE_FAILED \(error)\n", stderr)
            Settings.resetTestConfiguration()
            exit(1)
        }
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

@MainActor
private final class Probe {
    struct Owner {
        let path: String
        let key: String
        let layer: CALayer
        let installedBegin: CFTimeInterval
    }
    private let directory: URL
    init(_ directory: URL) { self.directory = directory }
    private func error(_ message: String) -> NSError {
        NSError(domain: "HistoryFixtureProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func write(_ value: Any, _ name: String) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name))
    }
    private func jsonValue<T>(_ value: T?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }
    func run() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var summaries: [[String: Any]] = []
        for policy in ["normal", "accessibility"] {
            for placement in ["original", "centered", "covered"] {
                for repetition in 1...3 {
                    for paused in [false, true] {
                        let report = try runCase(policy: policy, placement: placement,
                                                 repetition: repetition, paused: paused)
                        summaries.append(report)
                        try write(["schema": 1, "cases": summaries], "summary.json")
                    }
                }
            }
        }
        print("HISTORY_FIXTURE_PROBE_COMPLETED cases=\(summaries.count)")
    }
    private func pathVector(_ path: CGPath?) -> [[Double]]? {
        guard let path else { return nil }
        var result: [[Double]] = []
        path.applyWithBlock { pointer in
            let item = pointer.pointee
            let count: Int
            switch item.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            var row = [Double(item.type.rawValue)]
            for index in 0..<count {
                row.append(Double(item.points[index].x)); row.append(Double(item.points[index].y))
            }
            result.append(row)
        }
        return result
    }
    private func pathError(_ model: CGPath?, _ shown: CGPath?) -> Double? {
        guard let a = pathVector(model), let b = pathVector(shown), a.count == b.count,
              zip(a, b).allSatisfy({ $0.0.count == $0.1.count }) else { return nil }
        return zip(a.flatMap { $0 }, b.flatMap { $0 }).map { abs($0.0 - $0.1) }.max() ?? 0
    }
    private func clock(_ layer: CALayer, at now: CFTimeInterval) -> [String: Any] {
        ["localNow": layer.convertTime(now, from: nil), "speed": layer.speed,
         "beginTime": layer.beginTime, "timeOffset": layer.timeOffset,
         "hasSuperlayer": layer.superlayer != nil]
    }
    private func geometry(_ layer: CALayer) -> [String: Any] {
        var value: [String: Any] = ["position": [Double(layer.position.x), Double(layer.position.y)],
                                     "bounds": NSStringFromRect(layer.bounds)]
        if let shape = layer as? CAShapeLayer {
            value["path"] = jsonValue(pathVector(shape.path))
        }
        return value
    }
    private func owners(_ layer: CALayer, path: String = "root") -> [Owner] {
        var result = (layer.animationKeys() ?? []).filter { $0.hasPrefix("history.") }.compactMap { key -> Owner? in
            guard let animation = layer.animation(forKey: key) else { return nil }
            return Owner(path: path, key: key, layer: layer, installedBegin: animation.beginTime)
        }
        for (index, child) in (layer.sublayers ?? []).enumerated() {
            result += owners(child, path: path + "/sublayer\(index)")
        }
        if let mask = layer.mask { result += owners(mask, path: path + "/mask") }
        return result
    }
    private func snapshot(_ phase: String, start: CFTimeInterval, root: CALayer,
                          owners: [Owner], window: NSWindow, view: HistoryView) -> [String: Any] {
        let now = CACurrentMediaTime()
        let records = owners.map { owner -> [String: Any] in
            let layer = owner.layer, shown = layer.presentation()
            var row: [String: Any] = ["key": owner.key, "owner": owner.path,
                "ownerClock": clock(layer, at: now), "model": geometry(layer),
                "presentation": jsonValue(shown.map { geometry($0) }),
                "presentationClock": jsonValue(shown.map { clock($0, at: now) }),
                "installedAnimationBeginTime": owner.installedBegin]
            if let animation = layer.animation(forKey: owner.key) {
                row["animation"] = ["beginTime": animation.beginTime, "duration": animation.duration,
                    "speed": animation.speed, "timeOffset": animation.timeOffset,
                    "repeatCount": animation.repeatCount, "repeatDuration": animation.repeatDuration,
                    "autoreverses": animation.autoreverses, "removedOnCompletion": animation.isRemovedOnCompletion,
                    "configuredEndInOwnerTime": animation.beginTime + animation.duration,
                    "ownerElapsedSinceAnimationBegin": layer.convertTime(now, from: nil) - animation.beginTime,
                    "beginTimeChangedSinceInstall": animation.beginTime != owner.installedBegin]
            } else { row["animation"] = NSNull() }
            if let target = layer as? CAShapeLayer {
                row["fullPathMaximumError"] = jsonValue(pathError(target.path, (shown as? CAShapeLayer)?.path))
            }
            if let shown {
                row["positionError"] = hypot(shown.position.x - layer.position.x, shown.position.y - layer.position.y)
            }
            return row
        }
        return ["phase": phase, "mediaNow": now, "elapsed": now - start,
                "rootClock": clock(root, at: now),
                "rootPresentationClock": jsonValue(root.presentation().map { clock($0, at: now) }),
                "windowVisible": window.isVisible, "windowOcclusionVisible": window.occlusionState.contains(.visible),
                "windowFrame": NSStringFromRect(window.frame), "viewVisibleRect": NSStringFromRect(view.visibleRect),
                "viewHidden": view.isHiddenOrHasHiddenAncestor,
                "hasHistoryAnimations": view.hasChartAnimationForTest, "owners": records]
    }
    private func runApplication(until condition: @escaping () -> Bool) {
        func poll() {
            if condition() {
                NSApp.stop(nil)
                if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                    timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                    NSApp.postEvent(event, atStart: false)
                }
            } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() } }
        }
        DispatchQueue.main.async { poll() }
        NSApp.run()
    }
    private func runCase(policy: String, placement: String, repetition: Int, paused: Bool) throws -> [String: Any] {
        setenv("WATTSON_FORCE_LEGACY_KNOB", policy == "normal" ? "0" : "1", 1)
        setenv("WATTSON_FORCE_REDUCE_TRANSPARENCY", policy == "normal" ? "0" : "1", 1)
        // The real interaction harness explicitly enables History motion in both policies.
        setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
        Settings.colorScheme = .light; NSApp.appearance = Settings.ColorScheme.light.appearance
        let fixture = HistoryView()
        fixture.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth, height: HistoryView.preferredHeight)
        let container = NSView(frame: fixture.bounds); container.addSubview(fixture)
        let window = NSWindow(contentRect: fixture.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = container
        if placement != "original", let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - fixture.bounds.width / 2,
                                          y: screen.visibleFrame.midY - fixture.bounds.height / 2))
        }
        window.orderFront(nil); fixture.layoutSubtreeIfNeeded()
        fixture.setPresentationActive(true); fixture.setAnimationsEnabled(true)
        var cover: NSWindow?
        defer { fixture.setPresentationActive(false); cover?.close(); window.close() }
        fixture.update(samples: [], peak: 0, color: .systemBlue, timing: .init(sampledAt: [], referenceTime: 0))
        fixture.update(samples: [0, 0, 100], peak: 100, color: .systemBlue,
                       timing: .init(sampledAt: [0, 2, 4], referenceTime: 4))
        CATransaction.flush(); RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        if placement == "covered" {
            let blocker = NSWindow(contentRect: window.frame.insetBy(dx: -12, dy: -12),
                                   styleMask: .borderless, backing: .buffered, defer: false)
            blocker.isReleasedWhenClosed = false; blocker.isOpaque = true; blocker.backgroundColor = .gray
            blocker.orderFront(nil); cover = blocker
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let root = fixture.layer else { throw error("No production History root") }
        let pausedAt = root.convertTime(CACurrentMediaTime(), from: nil)
        if paused { PopoverStyle.setWithoutAnimation { root.speed = 0; root.timeOffset = pausedAt } }
        fixture.update(samples: [0, 0, 100, 150], peak: 150, color: .systemBlue,
                       timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6))
        let installed = owners(root)
        guard Set(installed.map(\.key)).isSuperset(of: ["history.stroke", "history.fill", "history.head"]),
              installed.allSatisfy({ owner in
                  guard let a = owner.layer.animation(forKey: owner.key) else { return false }
                  return abs(a.duration - 0.35) < 0.000001 && a.isRemovedOnCompletion
                      && a.repeatCount == 0 && a.repeatDuration == 0 && !a.autoreverses
              }) else { throw error("Fixture did not install the exact finite 0.35s transition") }
        let installTime = CACurrentMediaTime()
        var observations = [snapshot("installed-before-flush", start: installTime, root: root,
                                     owners: installed, window: window, view: fixture)]
        CATransaction.flush(); RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        observations.append(snapshot("installed-after-compositor-turn", start: installTime, root: root,
                                     owners: installed, window: window, view: fixture))
        if paused {
            PopoverStyle.setWithoutAnimation {
                root.speed = 1; root.timeOffset = 0; root.beginTime = 0
                root.beginTime = root.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
            }
            CATransaction.flush()
        }
        let start = CACurrentMediaTime()
        observations.append(snapshot("observe-start", start: start, root: root, owners: installed, window: window, view: fixture))
        var firstRemoved: Double?, keysAtOneSecond: Bool?, revealed = false
        runApplication {
            let elapsed = CACurrentMediaTime() - start
            if placement == "covered", !revealed, elapsed >= 1.25 {
                cover?.close(); cover = nil; revealed = true; CATransaction.flush()
                observations.append(self.snapshot("cover-removed", start: start, root: root,
                                                  owners: installed, window: window, view: fixture))
            }
            if !fixture.hasChartAnimationForTest && firstRemoved == nil { firstRemoved = elapsed }
            if elapsed >= 1 && keysAtOneSecond == nil { keysAtOneSecond = fixture.hasChartAnimationForTest }
            observations.append(self.snapshot("poll", start: start, root: root, owners: installed, window: window, view: fixture))
            return elapsed >= 5 || (elapsed >= 1.6 && !fixture.hasChartAnimationForTest)
        }
        let name = "\(policy)-\(placement)-\(repetition)-\(paused ? "paused" : "normal")"
        let summary: [String: Any] = ["name": name, "policy": policy, "placement": placement,
            "repetition": repetition, "paused": paused, "keysAtOneSecond": keysAtOneSecond ?? true,
            "firstAutomaticKeyRemovalElapsed": jsonValue(firstRemoved),
            "keysRemainAfterObservation": fixture.hasChartAnimationForTest,
            "observationSeconds": CACurrentMediaTime() - start, "samples": observations.count]
        try write(["schema": 1, "summary": summary, "observations": observations], name + ".json")
        print("HISTORY_PROBE_CASE \(name) keysAt1=\(keysAtOneSecond ?? true) remaining=\(fixture.hasChartAnimationForTest)")
        fflush(stdout)
        return summary
    }
}
