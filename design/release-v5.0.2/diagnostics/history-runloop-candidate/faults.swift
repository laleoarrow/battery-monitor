// Negative controls touch only the actual tested stroke key, in the test process.
let diagnosticFault = ProcessInfo.processInfo.environment["WATTSON_HISTORY_FAULT"] ?? "none"
var diagnosticFaultInjected = false
var diagnosticDecisionElapsed: CFTimeInterval?
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
