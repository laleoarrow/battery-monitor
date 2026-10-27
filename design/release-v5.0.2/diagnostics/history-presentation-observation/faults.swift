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
    if !ready { log("DIAGNOSTIC_VISIBILITY_UNCONTROLLED: continuing only as a bounded diagnostic") }
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
