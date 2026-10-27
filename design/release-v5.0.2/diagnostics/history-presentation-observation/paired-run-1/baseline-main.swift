import AppKit
import ApplicationServices
import Darwin
// Isolate appearance before any popover/footer is constructed; an installed
// app's saved choice must not change which baseline this harness exercises.
let settingsSuiteName = ProcessInfo.processInfo.environment["WATTSON_TEST_DEFAULTS_SUITE"]!
let settingsDefaults = UserDefaults(suiteName: settingsSuiteName)!
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
Settings.configureForTest(defaults: settingsDefaults)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func log(_ s: String) { print(s); fflush(stdout) }
var pass = true
func check(_ n: String, _ ok: Bool, _ d: String = "") {
    if !ok { pass = false }
    log("\(ok ? "✅" : "❌") \(n)\(d.isEmpty ? "" : "  — \(d)")")
}

/// A locked screen starts CoreAnimation but never finishes it, so anything
/// waiting on a close animation to complete hangs forever. Reporting that as a
/// failure would be inventing eight bugs that do not exist, and reporting it as
/// a pass would be worse. Say plainly that it could not be checked.
let screenLocked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Int == 1
let initialReduceMotionOverride = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"]
let forcedReduceMotion: Bool
switch initialReduceMotionOverride {
case "1": forcedReduceMotion = true
case "0": forcedReduceMotion = false
default: forcedReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
item.button?.image = NSImage(systemSymbolName: "battery.100", accessibilityDescription: nil)
guard let button = item.button else { log("no button"); exit(1) }
app.finishLaunching()                     // 少了这句状态栏按钮无法承载弹窗
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
func spin(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

// Concatenated into an extracted test harness, never into the app target.
// Negative controls touch only the actual tested stroke key, in the test process.
let diagnosticFault = ProcessInfo.processInfo.environment["WATTSON_HISTORY_FAULT"] ?? "none"
var diagnosticFaultInjected = false
var diagnosticDecisionElapsed: CFTimeInterval?
var diagnosticVisibility: [String: Any] = [:]

func requireDiagnosticVisibility(_ window: NSWindow) {
    // Shared by baseline and candidate, before the first original History input.
    // This preparation does not extend the one-second settling deadline.
    NSApp.activate(ignoringOtherApps: true)
    window.orderFrontRegardless()
    let started = CACurrentMediaTime()
    let deadline = started + 5
    var ready = false
    while CACurrentMediaTime() < deadline {
        NSApp.updateWindows()
        CATransaction.flush()
        ready = NSApp.isActive && window.isVisible && window.occlusionState.contains(.visible)
            && window.isOnActiveSpace && !window.isMiniaturized
        if ready { break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    diagnosticVisibility = ["ready": ready, "applicationActive": NSApp.isActive,
                            "windowVisible": window.isVisible,
                            "windowNotOccluded": window.occlusionState.contains(.visible),
                            "windowOnActiveSpace": window.isOnActiveSpace,
                            "windowMiniaturized": window.isMiniaturized,
                            "preparationElapsedSeconds": CACurrentMediaTime() - started,
                            "beforeOriginalHistoryInputs": true]
    try! JSONSerialization.data(withJSONObject: diagnosticVisibility, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: CommandLine.arguments[1] + ".precondition.json"), options: .atomic)
    guard ready else {
        log("DIAGNOSTIC_VISIBILITY_PRECONDITION_UNAVAILABLE")
        exit(3)
    }
}

func installDiagnosticFault(view: HistoryView) {
    guard diagnosticFault != "none" else { return }
    let owners = diagnosticLayers(view.layer).compactMap { $0 as? CAShapeLayer }.filter {
        $0.animation(forKey: "history.stroke") != nil
    }
    guard owners.count == 1, let owner = owners.first, let path = owner.path else {
        log("DIAGNOSTIC_FAULT_INJECTION_FAILED: original stroke owner missing")
        exit(2)
    }
    let animation = CABasicAnimation(keyPath: "path")
    // Identical geometry must never bypass the actual live-animation-key guard.
    animation.fromValue = path
    animation.toValue = path
    animation.beginTime = owner.convertTime(CACurrentMediaTime(), from: nil)
    animation.duration = 0.18
    switch diagnosticFault {
    case "infinite": animation.repeatCount = .infinity
    case "long": animation.duration = 2
    case "retained":
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
    default: exit(2)
    }
    owner.add(animation, forKey: "history.stroke")
    CATransaction.flush()
    guard view.hasChartAnimationForTest, owner.animation(forKey: "history.stroke") != nil else { exit(2) }
    diagnosticFaultInjected = true
    log("DIAGNOSTIC_FAULT_INJECTED \(diagnosticFault) key=history.stroke fromEqualsTo=true")
}

var diagnosticRecords: [[String: Any]] = []
var diagnosticOriginalPassed: Bool?

func diagnosticLayers(_ layer: CALayer?) -> [CALayer] {
    guard let layer else { return [] }
    return [layer] + (layer.sublayers ?? []).flatMap { diagnosticLayers($0) }
        + (layer.mask.map { diagnosticLayers($0) } ?? [])
}

func diagnosticPath(_ path: CGPath?) -> (types: [Int], points: [CGPoint])? {
    guard let path else { return nil }
    var types: [Int] = [], points: [CGPoint] = []
    path.applyWithBlock { pointer in
        let element = pointer.pointee
        types.append(Int(element.type.rawValue))
        let count: Int
        switch element.type {
        case .moveToPoint, .addLineToPoint: count = 1
        case .addQuadCurveToPoint: count = 2
        case .addCurveToPoint: count = 3
        default: count = 0
        }
        points += (0..<count).map { element.points[$0] }
    }
    return (types, points)
}

func recordContractedAxis(_ label: String, view: HistoryView, started: CFTimeInterval,
                          originalPassed: Bool) {
    let now = CACurrentMediaTime()
    let window = view.window
    let records: [[String: Any]] = diagnosticLayers(view.layer).enumerated().map { index, layer in
        let shown = layer.presentation()
        let keys = layer.animationKeys() ?? []
        let modelPath = diagnosticPath((layer as? CAShapeLayer)?.path)
        let shownPath = diagnosticPath((shown as? CAShapeLayer)?.path)
        let sameTopology = modelPath != nil && shownPath != nil
            && modelPath!.types == shownPath!.types && modelPath!.points.count == shownPath!.points.count
        let delta = sameTopology ? zip(modelPath!.points, shownPath!.points).map { model, presented in
            hypot(Double(model.x - presented.x), Double(model.y - presented.y))
        }.max() : nil
        let isHead = abs(layer.bounds.width - 5.2) < 0.000_001
            && abs(layer.bounds.height - 5.2) < 0.000_001 && layer.cornerRadius == 2.6
        return [
            "index": index, "name": layer.name ?? "unnamed", "hasPresentation": shown != nil,
            "isHead": isHead, "keys": keys,
            "modelPathTypes": modelPath?.types as Any? ?? NSNull(),
            "modelPathPoints": modelPath?.points.map { [$0.x, $0.y] } as Any? ?? NSNull(),
            "presentationPathPoints": shownPath?.points.map { [$0.x, $0.y] } as Any? ?? NSNull(),
            "samePathTopology": sameTopology,
            "maximumPathTargetErrorPoints": delta as Any? ?? NSNull(),
            "modelPosition": [layer.position.x, layer.position.y],
            "presentationPosition": shown.map { [$0.position.x, $0.position.y] } as Any? ?? NSNull(),
            "headTargetErrorPoints": (isHead ? shown.map {
                hypot(Double($0.position.x - layer.position.x), Double($0.position.y - layer.position.y))
            } : nil) as Any? ?? NSNull(),
            "localTime": layer.convertTime(now, from: nil), "speed": layer.speed,
            "beginTime": layer.beginTime, "timeOffset": layer.timeOffset,
            "animations": keys.compactMap { key -> [String: Any]? in
                guard let animation = layer.animation(forKey: key) else { return nil }
                return ["key": key, "beginTime": animation.beginTime, "duration": animation.duration,
                        "removedOnCompletion": animation.isRemovedOnCompletion,
                        "repeatCount": String(describing: animation.repeatCount)]
            },
        ]
    }
    diagnosticRecords.append([
        "observation": label, "elapsedSinceOriginalWaitStart": now - started,
        "originalDeadlineSeconds": 1, "originalAssertionPassed": originalPassed,
        "hasChartAnimation": view.hasChartAnimationForTest,
        "chartCeiling": view.chartCeilingForTest,
        "windowVisible": window?.isVisible ?? false,
        "windowOcclusionState": window?.occlusionState.rawValue ?? 0,
        "windowNotOccluded": window?.occlusionState.contains(.visible) ?? false,
        "windowOnActiveSpace": window?.isOnActiveSpace ?? false,
        "windowMiniaturized": window?.isMiniaturized ?? false,
        "visibleRect": NSStringFromRect(view.visibleRect),
        "hiddenOrHiddenAncestor": view.isHiddenOrHasHiddenAncestor,
        "screenLocked": (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Int == 1,
        "applicationActive": NSApp.isActive,
        "layers": records,
    ])
    let allKeys = records.flatMap { $0["keys"] as? [String] ?? [] }
    log("CONTRACTED_AXIS_OBSERVATION \(label) originalPassed=\(originalPassed) elapsed=\(now - started) keys=\(allKeys)")
}

func runApplication(until condition: @escaping () -> Bool,
                    timeout: TimeInterval) -> Bool {
    var satisfied = condition()
    let deadline = Date().addingTimeInterval(timeout)

    func stopApplicationLoop() {
        app.stop(nil)
        if let wake = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        ) {
            app.postEvent(wake, atStart: false)
        }
    }

    func poll() {
        satisfied = condition()
        guard !satisfied, Date() < deadline else {
            stopApplicationLoop()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
    }

    DispatchQueue.main.async { poll() }
    app.run()
    return satisfied
}

// ---- 14b. History: real hosted layers, bounded motion and lifecycle cancellation ----
var historyMotionChecksSkipped = false
if !screenLocked {
    let previousMotion = ProcessInfo.processInfo.environment["WATTSON_FORCE_REDUCE_MOTION"]
    let previousGlass = Settings.liquidGlassEnabled
    let previousModules = Settings.Module.allCases.map { ($0, Settings.isModuleVisible($0)) }
    defer {
        if let previousMotion { setenv("WATTSON_FORCE_REDUCE_MOTION", previousMotion, 1) }
        else { unsetenv("WATTSON_FORCE_REDUCE_MOTION") }
        for (module, visible) in previousModules { Settings.setModule(module, visible: visible) }
        Settings.liquidGlassEnabled = previousGlass
    }
    let skipHistoryMotion = initialReduceMotionOverride != "0" && initialReduceMotionOverride != "1"
        && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    if skipHistoryMotion { unsetenv("WATTSON_FORCE_REDUCE_MOTION") }
    else { setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1) }
    Settings.liquidGlassEnabled = false
    for module in Settings.Module.allCases { Settings.setModule(module, visible: module == .history) }

    func historyAnimations(_ layer: CALayer?) -> [(String, CAAnimation)] {
        guard let layer else { return [] }
        let own = (layer.animationKeys() ?? []).compactMap { key -> (String, CAAnimation)? in
            layer.animation(forKey: key).map { (key, $0) }
        }
        return own + (layer.sublayers ?? []).flatMap { historyAnimations($0) }
            + (layer.mask.map { historyAnimations($0) } ?? [])
    }
    func historyPathElements(_ path: CGPath) -> [(CGPathElementType, [CGPoint])] {
        var elements: [(CGPathElementType, [CGPoint])] = []
        path.applyWithBlock {
            let element = $0.pointee
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            elements.append((element.type, (0..<count).map { element.points[$0] }))
        }
        return elements
    }
    func alignedHistoryPathAnimation(_ animation: CAAnimation) -> Bool {
        guard let paths = historyStrokePaths(animation), let first = paths.first else { return false }
        let topology = historyPathElements(first).map { $0.0 }
        return !topology.isEmpty && paths.allSatisfy { path in
            let elements = historyPathElements(path)
            return elements.map { $0.0 } == topology
                && elements.flatMap { $0.1 }.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        }
    }
    func historyStrokePaths(_ animation: CAAnimation) -> [CGPath]? {
        guard let property = animation as? CAPropertyAnimation, property.keyPath == "path" else { return nil }
        let values: [Any]
        if let animation = animation as? CABasicAnimation,
           let from = animation.fromValue, let to = animation.toValue {
            values = [from, to]
        } else if let animation = animation as? CAKeyframeAnimation,
                  let frames = animation.values, frames.count == 9 {
            values = frames
        } else {
            return nil
        }
        var paths: [CGPath] = []
        for value in values {
            guard CFGetTypeID(value as CFTypeRef) == CGPath.typeID else { return nil }
            paths.append(value as! CGPath)
        }
        return paths
    }
    func validHistoryStroke(_ animation: CAAnimation, viewport: CATransform3D) -> Bool {
        guard let paths = historyStrokePaths(animation), let targetPath = paths.last else { return false }
        guard paths.count == 2 || paths.count == 9 else { return false }
        let target = historyPathElements(targetPath)
        guard !target.isEmpty else { return false }
        for (index, path) in paths.enumerated() {
            let elements = historyPathElements(path)
            guard elements.map({ $0.0 }) == target.map({ $0.0 }) else { return false }
            let progress = CGFloat(index) / CGFloat(paths.count - 1)
            let sx = viewport.m41 * (1 - progress)
            let sy = 1 + (viewport.m22 - 1) * (1 - progress)
            for (actual, final) in zip(elements, target) {
                guard actual.1.count == final.1.count,
                      actual.1.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return false }
                guard let a = actual.1.last, let b = final.1.last else { continue }
                let expectedY = HistoryView.chartHeight + (b.y - HistoryView.chartHeight) * sy
                guard abs(a.x - b.x - sx) < 0.01, abs(a.y - expectedY) < 0.01 else { return false }
            }
        }
        return true
    }
    func historyViewport(_ path: CGPath, target: CGPath) -> CATransform3D? {
        let shown = historyPathElements(path), final = historyPathElements(target)
        guard shown.map({ $0.0 }) == final.map({ $0.0 }),
              let first = shown.first?.1.last, let last = final.first?.1.last else { return nil }
        var transform = CATransform3DIdentity
        transform.m41 = first.x - last.x
        var largest: CGFloat = 0
        for (a, b) in zip(shown, final) {
            guard let p = a.1.last, let q = b.1.last else { continue }
            let height = HistoryView.chartHeight - q.y
            if height > largest {
                largest = height
                transform.m22 = (HistoryView.chartHeight - p.y) / height
            }
        }
        return largest > 0 && transform.m22.isFinite && transform.m22 > 0 ? transform : nil
    }
    func synchronizedHistoryPaths(_ stroke: CAAnimation?, _ fill: CAAnimation?) -> Bool {
        guard let stroke, let fill, alignedHistoryPathAnimation(stroke), alignedHistoryPathAnimation(fill),
              let a = historyStrokePaths(stroke), let b = historyStrokePaths(fill),
              abs(stroke.beginTime - fill.beginTime) < 0.000_001,
              stroke.duration == fill.duration, stroke.timingFunction == fill.timingFunction else { return false }
        return zip(a, b).allSatisfy { line, area in
            let p = historyPathElements(line).filter { $0.0 == .addCurveToPoint }.map { $0.1 }
            let q = historyPathElements(area).filter { $0.0 == .addCurveToPoint }.map { $0.1 }
            return !p.isEmpty && p == q
        }
    }
    func historyCubicMidpoint(_ path: CGPath, index: Int) -> CGPoint? {
        var current = CGPoint.zero
        var midpoints: [CGPoint] = []
        for (type, points) in historyPathElements(path) {
            if type == .addCurveToPoint {
                midpoints.append(CGPoint(x: (current.x + 3 * points[0].x + 3 * points[1].x + points[2].x) / 8,
                                         y: (current.y + 3 * points[0].y + 3 * points[1].y + points[2].y) / 8))
            }
            if let last = points.last { current = last }
        }
        return midpoints.indices.contains(index) ? midpoints[index] : nil
    }
    func historyDescendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + historyDescendants($0) }
    }
    let fixture = HistoryView()
    fixture.frame = NSRect(x: 0, y: 0, width: PopoverStyle.contentWidth,
                          height: HistoryView.preferredHeight)
    let container = NSView(frame: fixture.bounds)
    container.addSubview(fixture)
    let fixtureWindow = NSWindow(contentRect: fixture.bounds, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
    fixtureWindow.isReleasedWhenClosed = false
    fixtureWindow.contentView = container
    fixtureWindow.orderFront(nil)
    fixture.layoutSubtreeIfNeeded()
    fixture.setPresentationActive(true)
    fixture.setAnimationsEnabled(true)
    requireDiagnosticVisibility(fixtureWindow)
    defer { fixture.setPresentationActive(false); fixtureWindow.close() }
    var values = [40.0, 45.0]
    var times = [0.0, 2.0]
    func updateFixture(appending: Bool = true) {
        if appending { values.append(43); times.append(times.last! + 2) }
        fixture.update(samples: values, peak: 45, color: .systemBlue,
                       timing: HistoryChartTiming(sampledAt: times, referenceTime: times.last!))
        CATransaction.flush()
    }
    updateFixture(appending: false)
    check("History 首帧直接呈现而不伪造滚动", !fixture.hasChartAnimationForTest)

    // Explicit DEBUG overrides run the complete motion checks even on CI hosts
    // with Reduce Motion enabled. Without one, keep the real system policy.
    if skipHistoryMotion {
        updateFixture()
        check("History 遵守系统减少动态效果", !fixture.hasChartAnimationForTest)
        historyMotionChecksSkipped = true
        log("HISTORY_MOTION_CHECKS_SKIPPED: system Reduce Motion is enabled")
    } else {
        func settleHistoryFixture(_ context: String, view: HistoryView = fixture) -> Bool {
            if context == "contracted-axis" { installDiagnosticFault(view: view) }
            let started = CACurrentMediaTime()
            let settled = runApplication(until: { !view.hasChartAnimationForTest }, timeout: 1)
            if context == "contracted-axis" {
                diagnosticDecisionElapsed = CACurrentMediaTime() - started
                diagnosticOriginalPassed = settled
                recordContractedAxis("verdict-before-any-later-observation", view: view,
                                     started: started, originalPassed: settled)
            }


            if !settled {
                let remaining = historyAnimations(view.layer).map {
                    "\($0.0):\($0.1.duration)s"
                }.joined(separator: ",")
                log("HISTORY_COMPLETION_TIMEOUT \(context) elapsed=\(CACurrentMediaTime() - started) remaining=\(remaining)")
                let now = CACurrentMediaTime()
                func logClocks(_ layer: CALayer?) {
                    guard let layer else { return }
                    for key in layer.animationKeys() ?? [] {
                        guard let animation = layer.animation(forKey: key) else { continue }
                        let shown = layer.presentation()
                        log("HISTORY_OWNER_CLOCK key=\(key) localNow=\(layer.convertTime(now, from: nil)) speed=\(layer.speed) offset=\(layer.timeOffset) begin=\(layer.beginTime) presentationNow=\(shown?.convertTime(now, from: nil) ?? -1) animationBegin=\(animation.beginTime) duration=\(animation.duration) animationSpeed=\(animation.speed) animationOffset=\(animation.timeOffset) removed=\(animation.isRemovedOnCompletion)")
                    }
                    for child in layer.sublayers ?? [] { logClocks(child) }
                    logClocks(layer.mask)
                }
                logClocks(view.layer)
            }
            return settled
        }
        updateFixture()
        let animations = historyAnimations(fixture.layer)
        let animationKeys = Set(animations.map { $0.0 })
        check("History 连续真实采样启动同步描边、填充与末端动画",
              Set(["history.fill", "history.head", "history.stroke"]).isSubset(of: animationKeys)
                  && animationKeys.isSubset(of: ["history.head", "history.stroke", "history.fill", "history.reveal",
                                                 "history.gradient.startPoint", "history.gradient.endPoint"])
                  && animations.count == animationKeys.count && fixture.hasChartAnimationForTest)
        check("History 动画限于 180 ms 且没有重复、自动反向或常驻填充",
              animations.count >= 3 && animations.allSatisfy {
                  abs($0.1.duration - 0.18) < 0.000_001
                      && $0.1.repeatCount == 0 && $0.1.repeatDuration == 0
                      && !$0.1.autoreverses && $0.1.isRemovedOnCompletion
              })
        var ordinaryViewport = CATransform3DIdentity
        ordinaryViewport.m41 = CGFloat(2 / HistoryChartTiming.window) * PopoverStyle.contentWidth
        let ordinaryStroke = animations.first { $0.0 == "history.stroke" }?.1
        check("History 平移描边保持路径拓扑及真实采样位置",
              (animations.first { $0.0 == "history.head" }?.1 as? CAKeyframeAnimation)?.keyPath
                  == "position"
                  && ordinaryStroke is CABasicAnimation
                  && ordinaryStroke.map { validHistoryStroke($0, viewport: ordinaryViewport) } == true
                  && synchronizedHistoryPaths(ordinaryStroke, animations.first { $0.0 == "history.fill" }?.1))
        check("History 短过渡完成后原生图层自行静止", settleHistoryFixture("ordinary-scroll"))

        let cancellations: [(String, () -> Void, () -> Void)] = [
            ("结束呈现", { fixture.setPresentationActive(false) }, { fixture.setPresentationActive(true) }),
            ("关闭动画策略", { fixture.setAnimationsEnabled(false) }, { fixture.setAnimationsEnabled(true) }),
            ("隐藏视图", { fixture.isHidden = true }, { fixture.isHidden = false }),
            ("脱离窗口", { fixture.removeFromSuperview() }, { container.addSubview(fixture) }),
        ]
        for (name, cancel, restore) in cancellations {
            updateFixture()
            check("History \(name)前确实有活动动画", fixture.hasChartAnimationForTest)
            cancel()
            check("History \(name)立即移除动画", !fixture.hasChartAnimationForTest)
            updateFixture()
            check("History \(name)期间新采样不重启动画", !fixture.hasChartAnimationForTest)
            restore()
            check("History 恢复\(name)状态不重播旧过渡", !fixture.hasChartAnimationForTest)
        }

        // Axis changes must move through real presentation layers, including
        // when another reading arrives before the previous transition finishes.
        func historyLayers(_ layer: CALayer?) -> [CALayer] {
            guard let layer else { return [] }
            return [layer] + (layer.sublayers ?? []).flatMap { historyLayers($0) }
                + (layer.mask.map { historyLayers($0) } ?? [])
        }
        func viewportAnimation() -> (CAShapeLayer, CAPropertyAnimation)? {
            for case let layer as CAShapeLayer in historyLayers(fixture.layer) {
                if let animation = layer.animation(forKey: "history.stroke") as? CAPropertyAnimation {
                    return (layer, animation)
                }
            }
            return nil
        }
        func animationStart(_ animation: CAPropertyAnimation) -> CATransform3D? {
            guard let paths = historyStrokePaths(animation), let first = paths.first, let last = paths.last else { return nil }
            return historyViewport(first, target: last)
        }
        func projectedSample(_ watts: Double, sampledAt: Double, reference: Double,
                             ceiling: Double, transform: CATransform3D) -> CGPoint {
            CGPoint(x: CGFloat(1 - (reference - sampledAt) / HistoryChartTiming.window)
                            * PopoverStyle.contentWidth + transform.m41,
                    y: HistoryView.chartHeight * (1 - CGFloat(watts / ceiling) * transform.m22))
        }
        var axisValues = values
        var axisTimes = times
        func updateAxis(appending watts: Double) {
            axisValues.append(watts)
            axisTimes.append(axisTimes.last! + 2)
            if axisValues.count > 60 {
                axisValues.removeFirst()
                axisTimes.removeFirst()
            }
            fixture.update(samples: axisValues, peak: axisValues.max() ?? 0, color: .systemBlue,
                           timing: .init(sampledAt: axisTimes, referenceTime: axisTimes.last!))
            CATransaction.flush()
        }
        updateAxis(appending: 180)
        let expansion = viewportAnimation()
        let expansionStart = expansion.flatMap { animationStart($0.1) }
        check("History 新峰值扩轴使用有界的原生路径动画",
              fixture.chartCeilingForTest == 250 && expansion?.1.keyPath == "path"
                  && abs((expansion?.1.duration ?? 0) - 0.35) < 0.000_001
                  && expansion?.1.repeatCount == 0 && expansion?.1.autoreverses == false
                  && expansion?.1.isRemovedOnCompletion == true
                  && abs((expansionStart?.m22 ?? 0) - 250.0 / 55) < 0.000_001
                  && (expansionStart?.m41 ?? 0) > 0)
        let expansionPaths = historyAnimations(fixture.layer).filter {
            ($0.1 as? CAPropertyAnimation)?.keyPath == "path"
        }
        let expansionStroke = expansionPaths.first { $0.0 == "history.stroke" }?.1
        check("History 扩轴描边保持路径拓扑及真实采样位置",
              expansionStroke is CAKeyframeAnimation && expansionStroke.flatMap { stroke in
                  expansionStart.map { validHistoryStroke(stroke, viewport: $0) }
              } == true
                  && synchronizedHistoryPaths(expansionStroke,
                      expansionPaths.first { $0.0 == "history.fill" }?.1))
        let strokeLayer = historyLayers(fixture.layer).compactMap { $0 as? CAShapeLayer }.first {
            $0.animation(forKey: "history.stroke") != nil
        }
        let headLayer = historyLayers(fixture.layer).first {
            abs($0.bounds.width - 5.2) < 0.000_001
                && abs($0.bounds.height - 5.2) < 0.000_001 && $0.cornerRadius == 2.6
        }
        spin(0.1)
        let midExpansion = strokeLayer?.presentation()?.path.flatMap { path in
            fixture.chartPathForTest.flatMap { historyViewport(path, target: $0) }
        }
        check("History 扩轴中间帧位于起始范围与目标范围之间",
              (midExpansion?.m22 ?? 0) > 1
                  && (midExpansion?.m22 ?? .infinity) < (expansionStart?.m22 ?? 0))
        check("History 变轴保持末端圆点尺寸固定",
              headLayer?.presentation()?.bounds.size == CGSize(width: 5.2, height: 5.2)
                  && headLayer?.presentation()?.transform.m11 == 1
                  && headLayer?.presentation()?.transform.m22 == 1)
        var constantStrokeWidth = false
        if let presented = strokeLayer?.presentation() {
            let origin = presented.convert(CGPoint.zero, to: nil)
            let unitX = presented.convert(CGPoint(x: 1, y: 0), to: nil)
            let unitY = presented.convert(CGPoint(x: 0, y: 1), to: nil)
            let sx = hypot(Double(unitX.x - origin.x), Double(unitX.y - origin.y))
            let sy = hypot(Double(unitY.x - origin.x), Double(unitY.y - origin.y))
            constantStrokeWidth = abs(presented.lineWidth - 1.6) < 0.000_001
                && abs(sx - 1) < 0.000_001 && abs(sy - 1) < 0.000_001
        }
        check("History 变轴时描边宽度保持 1.6 点", constantStrokeWidth)
        let retainedTimestamp = axisTimes.first!
        let oldReference = axisTimes.last!
        let oldCeiling = fixture.chartCeilingForTest
        let beforeStrokePath = strokeLayer?.presentation()?.path
        let beforeRetarget = beforeStrokePath.flatMap { path in
            fixture.chartPathForTest.flatMap { historyViewport(path, target: $0) }
        }
        updateAxis(appending: 300)
        let retarget = viewportAnimation()
        let retargetStart = retarget.flatMap { animationStart($0.1) }
        let retargetStroke = historyAnimations(fixture.layer).first { $0.0 == "history.stroke" }?.1
        if let beforeStrokePath,
           let oldAnchor = historyPathElements(beforeStrokePath).first?.1.first,
           let firstStroke = retargetStroke.flatMap({ historyStrokePaths($0) })?.first,
           let newAnchor = historyPathElements(firstStroke).first?.1.first {
            check("History 中断变轴直接接续实际描边中的保留采样点",
                  abs(oldAnchor.x - newAnchor.x) < 0.5 && abs(oldAnchor.y - newAnchor.y) < 0.5)
        } else {
            check("History 中断变轴直接接续实际描边中的保留采样点", false)
        }
        if let beforeRetarget, let retargetStart {
            let before = projectedSample(axisValues[0], sampledAt: retainedTimestamp,
                                         reference: oldReference, ceiling: oldCeiling,
                                         transform: beforeRetarget)
            let after = projectedSample(axisValues[0], sampledAt: retainedTimestamp,
                                        reference: axisTimes.last!, ceiling: fixture.chartCeilingForTest,
                                        transform: retargetStart)
            check("History 中断扩轴从可见坐标接续保留采样点",
                  fixture.chartCeilingForTest == 350
                      && abs(before.x - after.x) < 0.5 && abs(before.y - after.y) < 0.5
                      && abs(retargetStart.m22 - 350.0 / 250) > 0.5)
        } else {
            check("History 中断扩轴从可见坐标接续保留采样点", false)
        }
        if let (layer, _) = retarget, let clip = layer.superlayer {
            let shown = layer.presentation() ?? layer
            let baseline = shown.convert(CGPoint(x: 0, y: HistoryView.chartHeight), to: clip.presentation() ?? clip)
            check("History 扩缩范围始终以图表底边为原点",
                  abs(baseline.x) < 0.000_001 && abs(baseline.y - HistoryView.chartHeight) < 0.000_001
                      && CATransform3DIsIdentity(shown.transform))
        } else {
            check("History 扩缩范围始终以图表底边为原点", false)
        }
        check("History 中断后的扩轴完成并自动静止", settleHistoryFixture("retargeted-axis"))

        // Evict the two high readings through the same 60-slot series. Only
        // then advance the four real sample ticks required by scale hysteresis.
        for _ in 0..<60 { updateAxis(appending: 43) }
        spin(0.3)
        check("History 旧峰值离开窗口后仍保留缩轴迟滞",
              axisValues.allSatisfy { $0 == 43 } && fixture.chartCeilingForTest == 350)
        for tick in 1...4 {
            updateAxis(appending: 43)
            if tick < 4 {
                check("History 缩轴第\(tick)个两秒采样仍保持旧范围",
                      fixture.chartCeilingForTest == 350)
            }
        }
        let contraction = viewportAnimation()
        let contractionStart = contraction.flatMap { animationStart($0.1) }
        check("History 八秒迟滞结束后缩轴平滑展开低功率数据",
              fixture.chartCeilingForTest == 50
                  && abs((contractionStart?.m22 ?? 0) - 50.0 / 350) < 0.000_001)
        spin(0.1)
        let contractionScale = contraction?.0.presentation()?.path.flatMap { path in
            fixture.chartPathForTest.flatMap { historyViewport(path, target: $0)?.m22 }
        }
        check("History 缩轴中间帧连续接近最终范围",
              (contractionScale ?? 0) > (contractionStart?.m22 ?? 1)
                  && (contractionScale ?? .infinity) < 1)
        check("History 缩轴结束后原生图层自行静止", settleHistoryFixture("contracted-axis"))
    }
}

NSStatusBar.system.removeStatusItem(item)
Settings.resetTestConfiguration()
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
let report: [String: Any] = [
    "schema": 1, "waitingStrategy": "baseline",
    "fault": diagnosticFault, "faultInjected": diagnosticFaultInjected,
    "visibilityBeforeHistoryInputs": diagnosticVisibility,
    "decisionElapsedSeconds": diagnosticDecisionElapsed as Any? ?? NSNull(),
    "globalRunApplicationUnchanged": true, "postDeadlineFlushAffectsVerdict": false,
    "method": "Extracted original History section through contracted-axis; preceding fixture lifecycle and all input updates retained.",
    "originalOneSecondDeadlineRetained": true, "originalContractedAxisPassed": diagnosticOriginalPassed as Any? ?? NSNull(),
    "allExtractedAssertionsPassed": pass, "animationKeysForciblyRemovedByDiagnostic": false,
    "fixtureClockPauseReached": false, "records": diagnosticRecords,
    "limitations": "Earlier non-History suite state is not replayed. Geometry observations are not display-frame or FPS measurements. Diagnostic geometry is collected only after the fixed verdict; no post-verdict flush is performed."
]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
exit(diagnosticOriginalPassed == nil ? 2 : pass ? 0 : 1)
