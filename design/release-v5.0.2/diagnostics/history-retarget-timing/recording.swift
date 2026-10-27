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
