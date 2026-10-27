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
var diagnosticChecks: [[String: Any]] = []
func check(_ n: String, _ ok: Bool, _ d: String = "") {
    diagnosticChecks.append(["name": n, "passed": ok])
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

// Diagnostic-only recording; never compiled into the product.
let diagnosticFixedClock = ProcessInfo.processInfo.environment["WATTSON_RETARGET_FIXED_CLOCK"] == "1"
let diagnosticDelay = ProcessInfo.processInfo.environment["WATTSON_RETARGET_DELAY"] == "1" ? 0.2 : 0.0
var diagnosticRetarget: [String: Any] = [:]
var diagnosticClocks: [[String: Any]] = []

func diagnosticClock(_ name: String, _ layer: CALayer) {
    let now = CACurrentMediaTime()
    diagnosticClocks.append(["phase": name, "mediaTime": now,
                             "localTime": layer.convertTime(now, from: nil),
                             "speed": layer.speed, "beginTime": layer.beginTime,
                             "timeOffset": layer.timeOffset])
}

func diagnosticAnimation(_ animation: CAAnimation?, owner: CALayer?) -> [String: Any] {
    guard let animation else { return [:] }
    let now = CACurrentMediaTime()
    return ["beginTime": animation.beginTime, "duration": animation.duration,
            "speed": animation.speed, "timeOffset": animation.timeOffset,
            "repeatCount": String(describing: animation.repeatCount),
            "removedOnCompletion": animation.isRemovedOnCompletion,
            "ownerLocalTime": owner?.convertTime(now, from: nil) as Any? ?? NSNull()]
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
        func historyLayers(_ layer: CALayer?) -> [CALayer] {
            guard let layer else { return [] }
            return [layer] + (layer.sublayers ?? []).flatMap { historyLayers($0) }
                + (layer.mask.map { historyLayers($0) } ?? [])
        }
        func settleHistoryFixture(_ context: String, view: HistoryView = fixture) -> Bool {
            let started = CACurrentMediaTime()
            let settled = runApplication(until: {
                // Observe the hosted presentation tree before committing its
                // completed transactions; live animation keys remain the gate.
                for layer in historyLayers(view.layer) {
                    if let presented = layer.presentation() {
                        _ = presented.position
                        if let shape = presented as? CAShapeLayer { _ = shape.path }
                    }
                }
                CATransaction.flush()
                return !view.hasChartAnimationForTest
            }, timeout: 1)
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
        let axisTimeline = fixture.layer!
        diagnosticClock("before-initial-expansion", axisTimeline)
        let axisPausedAt = axisTimeline.convertTime(CACurrentMediaTime(), from: nil)
        if diagnosticFixedClock {
            PopoverStyle.setWithoutAnimation {
                axisTimeline.speed = 0
                axisTimeline.timeOffset = axisPausedAt
            }
            CATransaction.flush()
        }
        let diagnosticExpansionRequestedAt = CACurrentMediaTime()
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
        if diagnosticFixedClock {
            PopoverStyle.setWithoutAnimation { axisTimeline.timeOffset = axisPausedAt + 0.1 }
            CATransaction.flush()
        }
        let diagnosticSpinStart = CACurrentMediaTime()
        spin(0.1)
        let diagnosticSpinEnd = CACurrentMediaTime()
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
        let diagnosticDelayStart = CACurrentMediaTime()
        if diagnosticDelay > 0 { spin(diagnosticDelay) }
        let diagnosticDelayEnd = CACurrentMediaTime()
        let diagnosticReadStart = CACurrentMediaTime()
        let diagnosticReadStartLocal = axisTimeline.convertTime(diagnosticReadStart, from: nil)
        let beforeStrokePath = strokeLayer?.presentation()?.path
        let diagnosticReadEnd = CACurrentMediaTime()
        let diagnosticReadEndLocal = axisTimeline.convertTime(diagnosticReadEnd, from: nil)
        let beforeRetarget = beforeStrokePath.flatMap { path in
            fixture.chartPathForTest.flatMap { historyViewport(path, target: $0) }
        }
        let diagnosticUpdateStart = CACurrentMediaTime()
        updateAxis(appending: 300)
        let diagnosticUpdateEnd = CACurrentMediaTime()
        let retarget = viewportAnimation()
        let retargetStart = retarget.flatMap { animationStart($0.1) }
        let retargetStroke = historyAnimations(fixture.layer).first { $0.0 == "history.stroke" }?.1
        if let beforeStrokePath,
           let oldAnchor = historyPathElements(beforeStrokePath).first?.1.first,
           let firstStroke = retargetStroke.flatMap({ historyStrokePaths($0) })?.first,
           let newAnchor = historyPathElements(firstStroke).first?.1.first {
            check("History 中断变轴直接接续实际描边中的保留采样点",
                  abs(oldAnchor.x - newAnchor.x) < 0.5 && abs(oldAnchor.y - newAnchor.y) < 0.5)
            diagnosticRetarget["oldAnchor"] = [oldAnchor.x, oldAnchor.y]
            diagnosticRetarget["newAnchor"] = [newAnchor.x, newAnchor.y]
            diagnosticRetarget["anchorDX"] = abs(oldAnchor.x - newAnchor.x)
            diagnosticRetarget["anchorDY"] = abs(oldAnchor.y - newAnchor.y)
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
            diagnosticRetarget.merge([
                "before": [before.x, before.y], "after": [after.x, after.y],
                "dx": abs(before.x - after.x), "dy": abs(before.y - after.y),
                "beforeRetargetM22": beforeRetarget.m22, "beforeRetargetM41": beforeRetarget.m41,
                "retargetStartM22": retargetStart.m22, "retargetStartM41": retargetStart.m41,
                "settledRatio": 350.0 / 250, "distanceFromSettledRatio": abs(retargetStart.m22 - 350.0 / 250),
                "newCeiling": fixture.chartCeilingForTest, "oldCeiling": oldCeiling,
                "ceilingPredicate": fixture.chartCeilingForTest == 350,
                "xPredicate": abs(before.x - after.x) < 0.5, "yPredicate": abs(before.y - after.y) < 0.5,
                "midTransitionPredicate": abs(retargetStart.m22 - 350.0 / 250) > 0.5,
                "retainedTimestamp": retainedTimestamp, "retainedWatts": axisValues[0],
                "oldReference": oldReference, "newReference": axisTimes.last!,
                "expansionAnimation": diagnosticAnimation(expansion?.1, owner: expansion?.0),
                "retargetAnimation": diagnosticAnimation(retarget?.1, owner: retarget?.0),
                "expansionRequestedAt": diagnosticExpansionRequestedAt,
                "spinRequestedSeconds": 0.1, "spinActualSeconds": diagnosticSpinEnd - diagnosticSpinStart,
                "extraDelayRequestedSeconds": diagnosticDelay,
                "extraDelayActualSeconds": diagnosticDelayEnd - diagnosticDelayStart,
                "sampleElapsedSinceExpansionRequest": diagnosticReadStart - diagnosticExpansionRequestedAt,
                "beforeStrokeReadStart": diagnosticReadStart, "beforeStrokeReadEnd": diagnosticReadEnd,
                "beforeStrokeLocalStart": diagnosticReadStartLocal, "beforeStrokeLocalEnd": diagnosticReadEndLocal,
                "update300Start": diagnosticUpdateStart, "update300End": diagnosticUpdateEnd,
                "windowVisible": fixtureWindow.isVisible,
                "windowNotOccluded": fixtureWindow.occlusionState.contains(.visible),
                "visibleRect": NSStringFromRect(fixture.visibleRect), "applicationActive": NSApp.isActive,
            ], uniquingKeysWith: { _, new in new })
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
        diagnosticClock("before-resume", axisTimeline)
        if diagnosticFixedClock {
            let axisResumeAt = axisTimeline.timeOffset
            PopoverStyle.setWithoutAnimation {
                axisTimeline.speed = 1
                axisTimeline.timeOffset = 0
                axisTimeline.beginTime = 0
                axisTimeline.beginTime = axisTimeline.convertTime(CACurrentMediaTime(), from: nil) - axisResumeAt
            }
            CATransaction.flush()
        }
        diagnosticClock("after-resume", axisTimeline)
        diagnosticRetarget["retargetAnimationAfterResume"] = diagnosticAnimation(retarget?.0.animation(forKey: "history.stroke"), owner: retarget?.0)
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
        let contractionSettled = settleHistoryFixture("contracted-axis")
        check("History 缩轴结束后原生图层自行静止", contractionSettled)

        // Equal geometry must not make the settling wait accept a live key.
        // Inject only after the real contraction has completed, then remove
        // only that test-owned stroke key before continuing the fixture.
        if contractionSettled, let stroke = contraction?.0, let path = stroke.path {
            let controls: [(String, CFTimeInterval, Float, Bool)] = [
                ("无限重复", 0.18, .infinity, true),
                ("两秒长动画", 2, 0, true),
                ("完成后保留", 0.18, 0, false),
            ]
            for (name, duration, repeatCount, removed) in controls {
                let animation = CABasicAnimation(keyPath: "path")
                animation.fromValue = path
                animation.toValue = path
                animation.beginTime = stroke.convertTime(CACurrentMediaTime(), from: nil)
                animation.duration = duration
                animation.repeatCount = repeatCount
                animation.isRemovedOnCompletion = removed
                if !removed { animation.fillMode = .forwards }
                stroke.add(animation, forKey: "history.stroke")
                CATransaction.flush()
                check("History \(name)反例确实注入真实描边键",
                      fixture.hasChartAnimationForTest && stroke.animation(forKey: "history.stroke") != nil)
                let started = CACurrentMediaTime()
                let settled = settleHistoryFixture("negative-control-\(name)")
                check("History \(name)反例在原一秒期限仍被拒绝",
                      !settled && CACurrentMediaTime() - started >= 1
                          && stroke.animation(forKey: "history.stroke") != nil)
                stroke.removeAnimation(forKey: "history.stroke")
                check("History \(name)反例仅清理注入键后恢复静止", !fixture.hasChartAnimationForTest)
            }
        } else {
            check("History 描边键反例具备已完成的真实缩轴夹具", false)
        }

        var cancellationPeak = 300.0
        for (name, cancel, restore) in cancellations {
            cancellationPeak *= 2
            updateAxis(appending: cancellationPeak)
            check("History \(name)前确实有活动变轴动画", viewportAnimation() != nil)
            cancel()
            check("History \(name)立即移除变轴与末端动画", !fixture.hasChartAnimationForTest)
            cancellationPeak *= 2
            updateAxis(appending: cancellationPeak)
            check("History \(name)期间新峰值不重启变轴", !fixture.hasChartAnimationForTest)
            restore()
            check("History 恢复\(name)状态不重播旧变轴", !fixture.hasChartAnimationForTest)
        }

        // Adding 150 W changes the terminal tangent of the retained 0→100 W
        // interval. Freeze only this fixture's layer clock to inspect its exact
        // first composited frame, rather than racing a running animation.
        fixture.update(samples: [], peak: 0, color: .systemBlue,
                       timing: .init(sampledAt: [], referenceTime: 0))
        fixture.update(samples: [0, 0, 100], peak: 100, color: .systemBlue,
                       timing: .init(sampledAt: [0, 2, 4], referenceTime: 4))
        CATransaction.flush()
        spin(0.02)
        let oldTailPath = fixture.chartPathForTest
        let oldTailCeiling = fixture.chartCeilingForTest
        if let timeline = fixture.layer {
            let pausedAt = timeline.convertTime(CACurrentMediaTime(), from: nil)
            PopoverStyle.setWithoutAnimation {
                timeline.speed = 0
                timeline.timeOffset = pausedAt
            }
            fixture.update(samples: [0, 0, 100, 150], peak: 150, color: .systemBlue,
                           timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6))
            CATransaction.flush()
            spin(0.03)
            let tailLine = historyLayers(fixture.layer).compactMap { $0 as? CAShapeLayer }.first {
                $0.animation(forKey: "history.stroke") != nil
            }
            let targetTailPath = fixture.chartPathForTest
            let targetTailCeiling = fixture.chartCeilingForTest
            if let oldTailPath, let targetTailPath,
               let oldMidpoint = historyCubicMidpoint(oldTailPath, index: 1),
               let targetMidpoint = historyCubicMidpoint(targetTailPath, index: 1),
               let visiblePath = tailLine?.presentation()?.path,
               let visiblePoint = historyCubicMidpoint(visiblePath, index: 1) {
                check("History 新增采样首帧保留原区间的实际呈现中点",
                      abs(visiblePoint.x - oldMidpoint.x) < 0.01
                          && abs(visiblePoint.y - oldMidpoint.y) < 0.01)
                let oldRawMidpoint = (1 - oldMidpoint.y / HistoryView.chartHeight) * oldTailCeiling
                let newRawMidpoint = (1 - targetMidpoint.y / HistoryView.chartHeight) * targetTailCeiling
                check("History 末段回归夹具确实覆盖新增样本造成的切线变化",
                      abs(oldRawMidpoint - 31.25) < 0.000_001
                          && abs(newRawMidpoint - 125.0 / 3) < 0.000_001
                          && abs(oldRawMidpoint - newRawMidpoint) > 10)
            } else {
                check("History 新增采样首帧保留原区间的实际呈现中点", false)
                check("History 末段回归夹具确实覆盖新增样本造成的切线变化", false)
            }
        } else {
            check("History 新增采样首帧保留原区间的实际呈现中点", false)
        }
        // Clock surgery is only for the exact first-frame assertion above.
        // Exercise natural completion on a fresh production layer tree whose
        // time space has never been paused, without cancellation during the wait.
        fixture.setPresentationActive(false)
        fixture.removeFromSuperview()
        let completionFixture = HistoryView()
        completionFixture.frame = container.bounds
        container.addSubview(completionFixture)
        completionFixture.layoutSubtreeIfNeeded()
        completionFixture.setPresentationActive(true)
        completionFixture.setAnimationsEnabled(true)
        completionFixture.update(samples: [0, 0, 100], peak: 100, color: .systemBlue,
                                 timing: .init(sampledAt: [0, 2, 4], referenceTime: 4))
        CATransaction.flush()
        func historyPathsMatch(_ target: CGPath?, _ shown: CGPath?) -> Bool {
            guard let target, let shown else { return false }
            let a = historyPathElements(target), b = historyPathElements(shown)
            return a.count == b.count && zip(a, b).allSatisfy { target, shown in
                target.0 == shown.0 && target.1.count == shown.1.count
                    && zip(target.1, shown.1).allSatisfy {
                        abs($0.x - $1.x) < 0.01 && abs($0.y - $1.y) < 0.01
                    }
            }
        }
        let baselineReady = runApplication(until: {
            historyLayers(completionFixture.layer).compactMap { $0 as? CAShapeLayer }
                .contains { $0.path == completionFixture.chartPathForTest
                    && historyPathsMatch($0.path, $0.presentation()?.path) }
        }, timeout: 1)
        check("History 完成检查从未暂停且已呈现的静态曲线开始",
              baselineReady && !completionFixture.hasChartAnimationForTest
                  && completionFixture.layer?.speed == 1
                  && completionFixture.layer?.timeOffset == 0)
        completionFixture.update(samples: [0, 0, 100, 150], peak: 150, color: .systemBlue,
                                 timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6))
        CATransaction.flush()
        let completionAnimations = historyAnimations(completionFixture.layer)
        check("History 末段完成检查确实启动有界描边、填充与末端动画",
              Set(["history.fill", "history.stroke", "history.head"])
                  .isSubset(of: Set(completionAnimations.map { $0.0 }))
                  && completionAnimations.allSatisfy {
                      $0.1.duration.isFinite && abs($0.1.duration - 0.35) < 0.000_001
                          && $0.1.repeatCount == 0 && $0.1.repeatDuration == 0
                          && !$0.1.autoreverses && $0.1.isRemovedOnCompletion
                  })
        let completionLayers = historyLayers(completionFixture.layer)
        let completionShapes = completionLayers.compactMap { $0 as? CAShapeLayer }.filter {
            $0.animation(forKey: "history.stroke") != nil || $0.animation(forKey: "history.fill") != nil
        }
        let completionHead = completionLayers.first { $0.animation(forKey: "history.head") != nil }
        let completionLine = completionShapes.first { $0.animation(forKey: "history.stroke") != nil }
        let targetTailPath = completionFixture.chartPathForTest
        let tailSettled = settleHistoryFixture("matched-tail-normal-clock", view: completionFixture)
        let pathsMatch = completionShapes.count == 2 && completionShapes.allSatisfy { shape in
            historyPathsMatch(shape.path, shape.presentation()?.path)
        }
        let headMatches: Bool
        if let completionHead, let shownHead = completionHead.presentation() {
            headMatches = abs(completionHead.position.x - shownHead.position.x) < 0.01
                && abs(completionHead.position.y - shownHead.position.y) < 0.01
        } else { headMatches = false }
        if let targetTailPath, let targetMidpoint = historyCubicMidpoint(targetTailPath, index: 1),
           let settledPath = completionLine?.presentation()?.path,
           let settledMidpoint = historyCubicMidpoint(settledPath, index: 1) {
            check("History 控制点过渡到达新曲线后自动静止",
                  abs(settledMidpoint.x - targetMidpoint.x) < 0.000_001
                      && abs(settledMidpoint.y - targetMidpoint.y) < 0.000_001
                      && tailSettled && pathsMatch && headMatches)
        } else {
            check("History 控制点过渡到达新曲线后自动静止", false)
        }
        completionFixture.setPresentationActive(false)
        completionFixture.removeFromSuperview()
        fixtureWindow.orderOut(nil)

        let controller = PopoverController()
        let snapshot = PowerSnapshot(percent: 50, plugged: true, adapterW: 45,
                                     batteryW: 5, systemW: 40)
        var hostedValues = [40.0, 45.0]
        var hostedTimes = [0.0, 2.0]
        func updateController(appending: Bool = true, degraded: Bool = false) {
            if appending { hostedValues.append(43); hostedTimes.append(hostedTimes.last! + 2) }
            controller.update(snapshot: snapshot, history: hostedValues, peak: 45, degraded: degraded,
                              historyTiming: HistoryChartTiming(sampledAt: hostedTimes,
                                                               referenceTime: hostedTimes.last!))
            CATransaction.flush()
        }
        updateController(appending: false)
        controller.openForSettingsCommandTest(relativeTo: button)
        spin(0.4)
        defer { controller.handleOutsideClick(); spin(0.4) }
        if let root = controller.contentViewForTest,
           let hosted = historyDescendants(root).compactMap({ $0 as? HistoryView }).first {
            root.layoutSubtreeIfNeeded()
            updateController()
            check("History 生产弹窗把动画策略传至实际栏目", hosted.hasChartAnimationForTest)
            Settings.setModule(.history, visible: false)
            check("History 关闭模块立即取消已有过渡", hosted.isHidden && !hosted.hasChartAnimationForTest)
            updateController()
            check("History 模块关闭后采样不会重启过渡", !hosted.hasChartAnimationForTest)
            Settings.setModule(.history, visible: true)
            let restoredWithoutReplay = !hosted.isHidden && !hosted.hasChartAnimationForTest
            // Let AppKit restore the viewport and commit the newest static path.
            // An immediate append could see the old, shorter presentation path.
            let restoreStarted = CACurrentMediaTime()
            var restoredBaselineCommitted = false
            let restoredHistoryReady = runApplication(until: {
                root.layoutSubtreeIfNeeded()
                CATransaction.flush()
                let model = hosted.chartPathForTest
                let stroke = historyLayers(hosted.layer).compactMap { $0 as? CAShapeLayer }
                    .first { $0.strokeColor != nil && $0.path == model }
                restoredBaselineCommitted = model != nil && stroke?.presentation()?.path == model
                return controller.isOpen && controller.isShownForTest
                    && hosted.window?.isVisible == true && !hosted.isHiddenOrHasHiddenAncestor
                    && !hosted.visibleRect.isEmpty && restoredBaselineCommitted
            }, timeout: 1)
            log("HISTORY_HOSTED_RESTORE_READY ready=\(restoredHistoryReady) baselineCommitted=\(restoredBaselineCommitted) elapsed=\(CACurrentMediaTime() - restoreStarted) visibleRect=\(hosted.visibleRect) bounds=\(hosted.bounds) windowVisible=\(hosted.window?.isVisible == true) hidden=\(hosted.isHiddenOrHasHiddenAncestor)")
            check("History 恢复模块直接呈现最新数据",
                  restoredWithoutReplay && restoredHistoryReady && !hosted.hasChartAnimationForTest)

            updateController()
            if !hosted.hasChartAnimationForTest {
                log("HISTORY_HOSTED_SAMPLE_NO_MOTION visibleRect=\(hosted.visibleRect) bounds=\(hosted.bounds) windowVisible=\(hosted.window?.isVisible == true) hidden=\(hosted.isHiddenOrHasHiddenAncestor) keys=\(historyAnimations(hosted.layer).map { $0.0 })")
            }
            check("History 失败前的有效采样确实启动过渡", hosted.hasChartAnimationForTest)
            updateController(appending: false, degraded: true)
            check("History 读取失败立即取消过渡", !hosted.hasChartAnimationForTest)
            updateController(degraded: true)
            check("History 过期数据不重启过渡", !hosted.hasChartAnimationForTest)
            updateController(appending: false)

            updateController()
            check("History 减少动态效果变化前确实启动过渡", hosted.hasChartAnimationForTest)
            setenv("WATTSON_FORCE_REDUCE_MOTION", "1", 1)
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: NSWorkspace.shared
            )
            spin(0.01)
            check("History 开启减少动态效果立即取消过渡", !hosted.hasChartAnimationForTest)
            updateController()
            check("History 减少动态效果期间采样保持静止", !hosted.hasChartAnimationForTest)
            setenv("WATTSON_FORCE_REDUCE_MOTION", "0", 1)
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: NSWorkspace.shared
            )
            spin(0.01)
            updateController()
            check("History 收起前确实有活动过渡", hosted.hasChartAnimationForTest)
            controller.handleOutsideClick()
            check("History 收起弹窗立即取消过渡", !hosted.hasChartAnimationForTest)
            updateController()
            check("History 弹窗关闭时新数据不会重启过渡", !hosted.hasChartAnimationForTest)
        } else {
            check("History 原生生命周期验证找到真实生产栏目", false)
        }
    }
}

NSStatusBar.system.removeStatusItem(item)
Settings.resetTestConfiguration()
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
let diagnosticReport: [String: Any] = [
    "schema": 1, "fixedFixtureClock": diagnosticFixedClock, "controlledDelaySeconds": diagnosticDelay,
    "allExtractedAssertionsPassed": pass, "checks": diagnosticChecks,
    "retarget": diagnosticRetarget, "clocks": diagnosticClocks,
    "originalHalfPointTolerancePreserved": true, "originalOneSecondWaitPreserved": true,
    "allHistoryAssertionsRetained": true, "nonHistoryPrefixReplayed": false,
    "screenLocked": screenLocked, "limitations": "Layer-property snapshots are not display-frame or FPS evidence."
]
try JSONSerialization.data(withJSONObject: diagnosticReport, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
if !pass {
    log("\nSOME_CHECKS_FAILED")
    exit(1)
}
// 跑过的都过了，但跳过的不能算验过
log(screenLocked || historyMotionChecksSkipped ? "\nRUNNABLE_CHECKS_PASSED_SOME_SKIPPED" : "\nALL_INTERACTION_CHECKS_PASSED")
exit(screenLocked || historyMotionChecksSkipped ? 2 : 0)
