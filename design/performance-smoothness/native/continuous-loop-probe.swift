import AppKit
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()
let suite = ProcessInfo.processInfo.environment["WATTSON_TEST_DEFAULTS_SUITE"]!
let defaults = UserDefaults(suiteName: suite)!
Settings.configureForTest(defaults: defaults)
let revision = CommandLine.arguments[1]
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let window = NSWindow(contentRect: .init(x: 120, y: 120, width: 360, height: 300),
                      styleMask: [.borderless], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.animationBehavior = .none
let host = NSView(frame: .init(x: 0, y: 0, width: 360, height: 300))
window.contentView = host
let normal = HistoryView(), frozen = HistoryView()
for (index, view) in [normal, frozen].enumerated() {
    view.frame = .init(x: 16, y: 10 + CGFloat(index) * 145,
                       width: PopoverStyle.contentWidth, height: HistoryView.preferredHeight)
    host.addSubview(view)
    view.setPresentationActive(true)
    view.setAnimationsEnabled(true)
    view.update(samples: [0, 0, 100], peak: 100, color: .systemBlue,
                timing: .init(sampledAt: [0, 2, 4], referenceTime: 4))
}
window.orderFront(nil)
host.layoutSubtreeIfNeeded()
CATransaction.flush()
var records = [[String: Any]]()
func points(_ path: CGPath?) -> Any {
    guard let path else { return NSNull() }
    var result = [[String: Any]]()
    path.applyWithBlock { pointer in
        let e = pointer.pointee
        let count: Int
        switch e.type {
        case .moveToPoint, .addLineToPoint: count = 1
        case .addQuadCurveToPoint: count = 2
        case .addCurveToPoint: count = 3
        default: count = 0
        }
        result.append(["type": e.type.rawValue,
                       "points": (0..<count).map { [e.points[$0].x, e.points[$0].y] }])
    }
    return result
}
func layers(_ layer: CALayer?) -> [CALayer] {
    guard let layer else { return [] }
    return [layer] + (layer.sublayers ?? []).flatMap { layers($0) }
        + (layer.mask.map { layers($0) } ?? [])
}
func capture(_ label: String, start: Double) {
    let now = CACurrentMediaTime()
    for (name, view) in [("normal", normal), ("frozen", frozen)] {
        let geometry: [[String: Any]] = layers(view.layer).enumerated().map { index, layer in
            let presentation = layer.presentation()
            let keys = layer.animationKeys() ?? []
            return [
                "index": index, "name": layer.name ?? "nil",
                "modelPath": points((layer as? CAShapeLayer)?.path),
                "presentationPath": points((presentation as? CAShapeLayer)?.path),
                "modelPosition": [layer.position.x, layer.position.y],
                "presentationPosition": presentation.map { [$0.position.x, $0.position.y] } ?? [],
                "isHead": abs(layer.bounds.width - 5.2) < 0.00001 && abs(layer.bounds.height - 5.2) < 0.00001,
                "localTime": layer.convertTime(now, from: nil),
                "speed": layer.speed, "beginTime": layer.beginTime, "timeOffset": layer.timeOffset,
                "presentationLocalTime": presentation?.convertTime(now, from: nil) ?? -1,
                "presentationSpeed": presentation?.speed ?? -1,
                "keys": keys,
                "animations": keys.map { key -> [String: Any] in
                    let animation = layer.animation(forKey: key)!
                    return ["key": key, "begin": animation.beginTime, "duration": animation.duration,
                            "removedOnCompletion": animation.isRemovedOnCompletion, "repeatCount": animation.repeatCount]
                },
            ]
        }
        records.append(["revision": revision, "instance": name, "observation": label,
                        "elapsed": now - start, "withinOneSecond": now - start <= 1,
                        "windowVisible": window.isVisible, "layers": geometry])
    }
}
var baselineCommitted = false
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
    capture("pre-update-baseline", start: CACurrentMediaTime())
    baselineCommitted = [normal, frozen].allSatisfy { view in
        layers(view.layer).compactMap { $0 as? CAShapeLayer }.filter { $0.path != nil }
            .allSatisfy { ($0.presentation() as? CAShapeLayer)?.path == $0.path }
    }
    guard let timeline = frozen.layer else { fatalError("No frozen fixture layer") }
    let pausedAt = timeline.convertTime(CACurrentMediaTime(), from: nil)
    PopoverStyle.setWithoutAnimation {
        timeline.speed = 0
        timeline.timeOffset = pausedAt
    }
    frozen.update(samples: [0, 0, 100, 150], peak: 150, color: .systemBlue,
                  timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6))
    CATransaction.flush()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
        normal.update(samples: [0, 0, 100, 150], peak: 150, color: .systemBlue,
                      timing: .init(sampledAt: [0, 2, 4, 6], referenceTime: 6))
        PopoverStyle.setWithoutAnimation {
            timeline.speed = 1
            timeline.timeOffset = 0
            timeline.beginTime = 0
            timeline.beginTime = timeline.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        }
        CATransaction.flush()
        let start = CACurrentMediaTime()
        capture("committed-start", start: start)
        for delay in [0.45, 0.85, 0.98] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                capture("scheduled-\(delay)", start: start)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let report: [String: Any] = ["schema": 1, "revision": revision,
                "baselineCommittedBeforeUpdates": baselineCommitted,
                "eventLoopRuns": 1, "stopsDuringObservation": 0,
                "records": records]
            try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output, options: [.atomic])
            app.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0) { app.postEvent(event, atStart: false) }
        }
    }
}
app.run()
window.close()
Settings.resetTestConfiguration()
defaults.removePersistentDomain(forName: suite)
_ = defaults.synchronize()
